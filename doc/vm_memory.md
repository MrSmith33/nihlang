This is a VM for CTFE (Compile-time function execution) for Vox programming language. The VM must model the target architecture. One of the factors is pointer size. 64 and 32 bit pointers should be supported. 32bit pointers are still relevant due to wasm32 target. Memory should work as in C-like language which Vox is.  
The consequence is that each byte of memory can be individually changed in arbitrary way due to the presence of unions, pointer arithmetic and tagged pointers.  
But we don't want compiler to crash when it will execute the code that does something nasty. We want a nice error message instead.  
As this VM will be used for CTFE, it means we may execute initialization code for static variables. Would be nice if any code could be run during compile-time and the result was nicely transformed into static data. This should include dynamic memory allocation.  
What we want is to gather all data reachable through pointers of the result to be placed into static memory of the executable. Other initializers now can use that data in read-only mode in their calculations.  

```d
LookupTable table1 = calc1(); // run calc1() at compile-time
i32 bar = calc2(table1);      // run calc2() at compile-time
```

Here `LookupTable` may contain pointers to the data allocated in `calc1()` call, which we want to end up in static memory.

We need to know what memory bytes contain a pointer and which contain bytes that only look like a pointer.

1. Why do we need to know where pointers are in each memory allocation?  
   We want each allocation to be a separate object during linking.  
   This gives us:
   - Ability to strip unused data
   - Reorder and compact data, so it takes minimal space
   - If the allocation will end up in the executable later, its address will be diffrent. Which means that for every pointer to another allocation linker needs to have a relocation entry, so each pointer value can be adjusted to pointer to correct address
   All this is relevant to transferring allocations from heap to static memory in CTFE, although it is possible to not move any allocations at all.

2. Why don't we just use the raw pointer in the VM memory?     
   Each pointer can be the size of the target architecture. It can point to some bound-checked arena.  
   Since we have raw access to all memory bytes, the code could forge pointers or make tagged pointers, and we wouldn't discover them later. So, we are trying to interpret each possible 32/64-bit sequence as a pointer and see if this is a valid one. Conservative way. Like in conservative GCs.  

   This has 2 problems:
   1) False positives  
      We can find that some byte sequence can be interpreted as a valid pointer.  

      If we assume it to be a real pointer, we would have the following potential situations:
      - False dependency of one allocation to another. This may result in an allocation that is not reachable from root pointers, to become reachable. So it will end up in static memory, bloating the executable. This does not pose any correctness problems.
      - Data corruption. When compiler/linker/loader need to move the target allocation, the pointer data will be updated, changing the original bytes of false pointer. The data is different from the result of CTFE.
   2) False negatives  
      Pointer may be disguised by some pointer tagging scheme (like using top 16 bits of 64bit pointer).  
      In this case we wouldn't find the pointer. It will not be added to relocation list. And when address changes, the pointer value will not be updated, resulting in the pointer pointing to the wrong location.
   
   The solution to this problem is to use "Shadow pointers"  
   The shadow pointer is when code cannot directly access the pointer base. In shadow pointer scenario the bytes that comprise the pointer (4 or 8 bytes) only store the offset inside the target allocation, while the pointer base is stored in a parallel data structure, like hashmap. Originally I saw this idea in presentation on constant evaluation in [MIRI](https://www.youtube.com/watch?v=5Pm2C1YXrvM) which is Rust IR interpreter.

Main problem that is solved by shadow pointers is precise pointer discovery.  
This is needed because after code finishes running during CTFE, all memory reachable through return value should become static memory. This is essentially copying GC.  
We need to have info per allocation anyway, if we want moving allocations around. Allocation info is (size, alignment, arena offset, memory kind, relocations, byte initialization mask)

Secondary to that shadow pointers can be used to detect multiple errors:
- Reading/writing with null/invalid pointer
- Reading/writing out of bounds of the allocation
- Subtraction of pointers of different allocations
- Adding two pointers together

Allocation metadata is useful for detecting:
- Writing to read-only memory
- Uninitialized memory access

3. How to model address space if we use shadow pointers? Linear memory or individual allocations or both?
   - Shadow pointer stores the offset into the linear address space.
     1. How do we get allocation metadata from the pointer?
   - Shadow pointer stores allocation index and memory offset. This way we can access the memory through the offset immediately, but we still need metadata to do bounds checking, so no cache gain here.
   - Shadow pointer stores allocation index. Allocation metadata stores the data offset + size.  
     This is the current one. But some features may require adding generation index to the shadow pointer to help find stale pointers.

I decided to use 4 pointer kinds:
- Static memory. We only append static initializers to it and copy reachable heap allocations. Data lives until the backend is involved.
- Heap memory. Used for dynamic allocations. Allocations can be marked as freed. This memory is wiped after each CTFE run, after reachable allocations are copied to static memory.
- Stack memory. Stores stack slots of function frames. This memory grows and shrinks like a stack, so having it as a separate arena seems efficient. Distinguishing it from the others is useful if we want to detect dangling pointers to stack memory.
- Non-memory references like function pointers. You cannot read/write through these, but you can call functions, or pass them to external functions. Can be used for unforgable tokens, for example for permission system.

4. Only allow aligned pointers?
   - Yes (most likely choice)  
     8 times less bits for pointer bitmap  
     Trap for unaligned pointer store  
   - No (Allow unaligned pointers)  
     What if pointers overlap?
     - Allow that (most likely choice)
     - Trap  
       Need to check in pointer bitmap if written pointer will overlap with existing pointers  
       That means checking ptrSize-1 bits to the left and to the right of the target address  
       This option is highly likely results in poor performance

5. Why do we need pointer bitmap?  
   We need memcopy/memmove instructions that are aware of shadow pointers  
   Without them the only way to copy a pointer is to perform a load of ptrSize instruction on the correct location, and then store to correct location, accounting for the choice in (4).  
   For that we basically need to have exact type info, which we don't have as this is an initial design decision for this VM.  
   Naive implementation of memcopy needs to check for every location where pointer can potentially be located in both source and destination memory. But hashmap doesn't have a way to iterate over the range of keys. Hence we can introduce a bitmap for quick checking if any pointers are present.  
   - Source memory pointers are checked so, that they are copied to the destination memory
   - Destination pointers need to be erased, and reference counts decreased  
   If we allow unaligned pointers then we would need:
   - 4/8 times as much bits in the bitmap.
   - if we trap on overlapped pointers, then we need to check a lot of bits on both bitmaps, which doesn't sound performant

6. How to detect escaped references to stack allocations?  
   Solutions that trap on load must handle the case where allocation struct is reused
   - Reference count each allocation and when function returns, check if any remaining references point to stack allocations of the frame  
     Pro: No need for generation index in the pointer  
     Pro: Detects escaped stack reference when function returns  
     Con: Need 32bit reference count in the allocation metadata (same as 32bit generation index)  
     Con: Need to increase/decrease refcount on every pointer write/pointer erase

     Parent frame registers can not contain pointers to current stack frame.  
     We need to check result registers when function ends.
   - Use generation index for allocations and references. Dead stack allocations will have their generation increased, so that dangling pointers can be detected when they are used.  
     Pro: should be faster than refcounting  
     Pro: works for external references (stored outside of VM)  
     Con: 32bit generation is stored in allocation metadata (same as 32bit refcount) and in each pointer  
     Con: Can only detect when pointer is accessed
   - Use some sort of GC that runs on each stack frame end to find all references to stack allocations  
     Pro: No extra data needs to be stored  
     Pro: No instrumentation like in refcounting, only at the end of function  
     Pro: Detects escaped stack reference when function returns  
     Con: Need to traverse the whole heap/stack/static memory (iterate through the hashmap of relocations, that contains pointers)

     This may use some sort of write-barrier where we store info about which pointers point to the stack allocation.

   We can have this code behind a callback, so that we can have multiple implementations with compile time switch.  
   If we define all this in terms of handlers that handle:
   1. Store that changes a memory slot
      - no pointer -> pointer
      -    pointer -> different pointer
      -    pointer -> no pointer
   2. On frame end
   3. On pointer deref

7. Is null a pointer or absense of pointer?  
   For now it an absense of pointer, so when null is written to memory, we just remove pointer from the destination if any.

8. Reading from uninitialized register
   - trap
   - conservative check in validation
   - allow and return garbage (potentially insecure and undeterministic)
   - allow and return zero

9. What opcodes must be aware of shadow pointers?
    1. Any register assignment must erase the pointer
    2. mov instructions should copy pointer value
    3. load
    4. store
    5. add  
       ptr + int  
       int + ptr trap  
       ptr + ptr trap
    6. sub  
       ptr - int  
       ptr - ptr (pointer bases must be equal, otherwise trap)  
       int - ptr trap
    7. memcopy, memmove, memcmp
    8. cmp
       eq, ne also check the pointer
       gt, ge trap if pointer is not the same
       Only unsigned integer compares should check for pointers
    9. branch
       jumps if either data or pointer is not zero

10. What if we memcopy a chunk of memory containing a pointer?  
    Memcopy must be aware of shadow pointers, but checking each word in the hashmap for potential pointer seems slow.  
    I think of using a bitmap, with one bit per pointer slot. This implies supporting aligned pointers only.  
    Then memcopy would copy a bitmap too. Plus for each 1 in the bitmap it would also look into the hashmap and copy the entry.  
    When memcopy copies a pointer, the pointer must land into aligned memory location. (Same with a store of a pointer)

11. What happens when load_m64 tries to load two 32-bit pointers?
    - Only load raw bytes (current solution)
    - trap
    - Somehow support 2 pointers per register. This would probably mean supporting several arithmetic operations, like shifting left/right by 32.

12. If we overwrite the whole pointer with small writes, should it remain the pointer? (yes)

VM limitations:
- Only aligned pointers
- Pointers are only copied by the pointer-sized load/store or memcopy that covers whole pointer
- Each allocation is in its own address space. You cannot subtract pointer to one allocation from pointer to a different one.

I can choose the definition of safety for my lang. Accessing a dangling pointer is definitely a problem. Having dangling pointers in memory after the end of CTFE is also a problem. But triggering on programs that have some sort of allocator, where there can be some stale memory with old pointers feels not practical. At the same time triggering as early as possible seems the most convenient when trying to find the cause of a problem.
Maybe the middle ground is to trigger conservatively. Then rerun all the computation looking for particular free operation and report it. I can do this if I make all the side-effects idempotent.

Possible fix is to insert some sort of clear/clear_shadow_pointers/mark_uninitialized call, when running in CTFE. This means that for some code that needs to run in both CTFE and native target, it needs this special call added. Pretty practical I would say.
```d
void clearBuffer() {
    length = 0;
    // clears all shadow pointers in memory slice when run in VM
    // no-op in native code
    __mark_uninitialized(bufPtr, capacity);
}
```

Open questions:
1. Should we allow static memory to contain uninitialized bytes?
2. Is it better to store a relocation hashmap per allocation or per memory?
3. Should a store of a register to memory be an error, when register contains a pointer and store size != ptr size? (yes)
4. Should we have a load_ptr/store_ptr instructions?
5. Should we have 2 kinds of registers?  
   One for non-pointer data  
   One for shadow pointers  
   Con: The consequence is that code must 100% know when something that is being loaded into register is a pointer.  
   Pro: No need to store pointer data for non-pointers