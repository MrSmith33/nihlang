/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.memory;

import vox.lib;
import vox.types;
import vox.vm.feature_flags;

@nogc nothrow:

struct AllocId {
	@nogc nothrow:
	this(u32 index, MemoryKind kind) {
		this.payload = (index & ((1 << 30) - 1)) | (kind << 30);
	}

	private u32 payload;

	u32 index() const {
		return cast(u32)(payload & ((1 << 30) - 1));
	}

	// kind: heap, stack, static, function
	MemoryKind kind() const {
		return cast(MemoryKind)(payload >> 30);
	}

	bool isDefined() const { return payload != 0; }
	bool isUndefined() const { return payload == 0; }

	void toString(scope SinkDelegate sink, FormatSpec spec) @nogc nothrow const {
		if (isDefined) {
			sink.formattedWrite("%s%s", memoryKindLetter[kind], index);
		} else {
			sink("null");
		}
	}
}

struct PointerId {
	@nogc nothrow:
	u32 index;
	alias index this;
}

struct Allocation {
	@nogc nothrow:

	// All allocations are aligned to 8 bytes in Memory buffer
	enum ALLOCATION_GRANULARITY = 8;

	this(u32 _offset, SizeAndAlign _sizeAlign, MemoryFlags perm) {
		flags = perm;
		offset = _offset;
		sizeAlign = _sizeAlign;
	}

	// MemoryFlags
	u32 flags;
	// Start in parent Memory.memory
	// Aligned to ALLOCATION_GRANULARITY
	u32 offset;
	// Size in bytes
	SizeAndAlign sizeAlign;
	// How many pointers to this allocation exist in other allocations
	// Pointers in registers do not increment the numInRefs
	u32 numInRefs;

	static if (OUT_REFS_PER_ALLOCATION) {
		HashMap!(u32, AllocId, u32.max) outRefs;
		u32 numOutRefs() { return outRefs.length; }
	} else {
		// How many pointers to this allocation contains.
		// Equivalent to Allocation.outRefs.length.
		u32 numOutRefs;
	}

	u32 alignedSize() const {
		pragma(inline, true);
		return alignValue(sizeAlign.size, ALLOCATION_GRANULARITY);
	}

	u32 size() const {
		pragma(inline, true);
		return sizeAlign.size;
	}

	bool isPointerValid(AllocId ptr) {
		pragma(inline, true);
		// In case generation index is added, it should be checked against ptr.generation
		return !isFreed;
	}

	bool isReadable() const { return (flags & MemoryFlags.read) != 0; }
	bool isWritable() const { return (flags & MemoryFlags.write) != 0; }
	// If true, when heap allocation is moved to static memory,
	// that static memory will be writable at runtime.
	bool isRuntimeWritable() const { return (flags & MemoryFlags.runtime_write) != 0; }
	bool isFreed() const { return (flags & MemoryFlags.isFreed) != 0; }
	bool isMarked() const { return (flags & MemoryFlags.isMarked) != 0; }

	void setPermission(MemoryFlags perm) {
		pragma(inline, true);
		flags = (flags & ~0b11) | u32(perm & 0b11);
	}

	void markFreed() {
		assert(!isFreed, "double free detected");
		flags |= MemoryFlags.isFreed;
		setPermission(MemoryFlags.none);
	}

	void markAsMovedToStaticMem(AllocId static_index) {
		flags |= MemoryFlags.isMarked;
		assert(static_index.kind == MemoryKind.static_mem, "static_index must be in static memory");
		numInRefs = static_index.index;
	}
	AllocId getStaticMemIndex() {
		assert(isMarked);
		return AllocId(numInRefs, MemoryKind.static_mem);
	}
}

struct Memory {
	@nogc nothrow:

	// How many bytes are used out of memory.reserved bytes
	u32 bytesUsed;
	// What memory is this
	MemoryKind kind;
	// How big is the pointer
	PtrSize ptrSize;

	// Individual allocations
	Array!Allocation allocations;
	// Actual memory bytes
	Array!u8 memory;
	// 1 bit per pointer slot
	// Pointers must be aligned in memory
	// Each allocation is aligned at least to a pointer size
	Array!u8 pointerBitmap;
	static if (SANITIZE_UNINITIALIZED_MEM) {
		// 1 bit per byte in memory
		// 1 means byte is initialized, 0 uninitialized
		Array!u8 initBitmap;
	}
	// Stores pointer data for every pointer in memory
	// This maps memory offset to AllocId
	static if (OUT_REFS_PER_MEMORY) {
		HashMap!(u32, AllocId, u32.max) outRefs;
	}

	void reserve(ref VoxAllocator allocator, u32 size) {
		memory.voidPut(allocator, size);
		// By default no pointers are in memory
		u8[] data1 = pointerBitmap.voidPut(allocator, divCeil(size, ptrSize.inBits));
		data1[] = 0;
		static if (SANITIZE_UNINITIALIZED_MEM) {
			// By default all bytes are uninitialized
			u8[] data2 = initBitmap.voidPut(allocator, divCeil(size, Allocation.ALLOCATION_GRANULARITY));
			data2[] = 0;
		}
	}

	void clear(ref VoxAllocator allocator) {
		static if (OUT_REFS_PER_ALLOCATION) {
			foreach(ref alloc; allocations) {
				alloc.outRefs.free(allocator);
			}
		} else {
			outRefs.clear;
		}
		static if (SANITIZE_UNINITIALIZED_MEM) {{
			markInitBits(0, bytesUsed, false);
			static if (SLOW_CHECKS) {
				usz numBits = countInitBits(0, initBitmap.length * 8);
				if (numBits) panic("%s.clear: Invariant failed. init bitmap contains %s bits after reset", memoryKindString[kind], numBits);
			}
		}}
		markPointerBits(PointerId(0), bytesUsed / ptrSize.inBytes, false);
		static if (SLOW_CHECKS) {{
			usz numBits = countPointerBits(0, pointerBitmap.length * 8);
			if (numBits) panic("%s numPointerBits %s", memoryKindString[kind], numBits);
		}}
		allocations.clear;
		bytesUsed = 0;
	}

	AllocId allocate(ref VoxAllocator allocator, SizeAndAlign sizeAlign, MemoryFlags perm) {
		u32 index = allocations.length;
		u32 offset = bytesUsed;
		assert(offset % Allocation.ALLOCATION_GRANULARITY == 0);
		// allocate in multiple of ALLOCATION_GRANULARITY bytes
		// so that pointers are always aligned in memory and we can use pointer bitmap
		u32 alignedSize = alignValue(sizeAlign.size, Allocation.ALLOCATION_GRANULARITY);
		bytesUsed += alignedSize;
		if (bytesUsed >= memory.length) panic("Out of %s memory", memoryKindString[kind]);
		allocations.put(allocator, Allocation(offset, sizeAlign, perm));
		static if (SLOW_CHECKS) {
			const PointerId fromSlot = memOffsetToPtrIndex(offset, ptrSize);
			const PointerId numSlots = memOffsetToPtrIndex(alignedSize, ptrSize);
			if(auto numBits = countPointerBits(fromSlot, numSlots) != 0) {
				panic("Pointer bitmap wasn't cleared, found %s bits in freshly allocated memory", numBits);
			}
		}
		return AllocId(index, kind);
	}

	// only for stack allocations
	// assumes all allocations to be in sequential order in memory
	// Doesn't clear outRefs or pointer bitmap
	void popAllocations(ref VoxAllocator allocator, u32 howMany) {
		assert(allocations.length >= howMany);
		allocations.unput(howMany);

		const auto lastByte = bytesUsed;

		if (allocations.length) {
			bytesUsed = allocations.back.offset + allocations.back.alignedSize;
		} else {
			bytesUsed = 0;
		}

		// clean init bits
		static if (SANITIZE_UNINITIALIZED_MEM) {
			markInitBits(bytesUsed, lastByte - bytesUsed, false);
		}
	}

	void popAndShiftAllocations(ref VoxAllocator allocator, u32 from, u32 to) {
		assert(to <= allocations.length);
		assert(from <= to);
		if (from == to) return;
		if (to == allocations.length) return popAllocations(allocator, to - from);

		const u32 fromByte = allocations[from].offset;
		const u32 toByte   = allocations[to - 1].offset + allocations[to - 1].alignedSize;
		const u32 lastByte = allocations.back.offset + allocations.back.alignedSize;
		const u32 shiftedBytes = lastByte - toByte;

		// copy allocations
		Allocation* allocationsDst = &allocations[from];
		const Allocation* allocationsSrc = &allocations[to];
		const u32 shiftedAllocations = allocations.length - to;
		memmove(allocationsDst, allocationsSrc, shiftedAllocations * Allocation.sizeof);

		// copy memory
		u8* memoryDst = &memory[fromByte];
		const u8* memorySrc = &memory[toByte];
		memmove(memoryDst, memorySrc, shiftedBytes);

		// update allocations
		const u32 byteOffset = toByte - fromByte;
		foreach(ref alloc; allocations[from..from + shiftedAllocations]) {
			alloc.offset = alloc.offset - byteOffset;
		}

		const PointerId fromSlot = memOffsetToPtrIndex(fromByte, ptrSize);
		const PointerId toSlot   = memOffsetToPtrIndex(toByte, ptrSize);
		const PointerId lastSlot = memOffsetToPtrIndex(lastByte, ptrSize);
		const u32 shiftedSlots   = lastSlot - toSlot;

		// check that all pointers were removed
		static if (SLOW_CHECKS) {
			if(auto numBits = countPointerBits(fromSlot, toSlot - fromSlot) != 0) {
				panic("Pointer bitmap wasn't cleared, found %s bits", numBits);
			}
		}

		// copy pointer bits
		usize* pointerBits = cast(usize*)&pointerBitmap.front();
		copyBitRange(pointerBits, pointerBits, fromSlot, toSlot, shiftedSlots);

		// clean trailing pointer bits
		markPointerBits(PointerId(fromSlot + shiftedSlots), toSlot - fromSlot, false);

		// update outRefs in shifted allocations
		// target outRefs is already cleaned by pre_drop_stack_range
		static if (OUT_REFS_PER_MEMORY) {
			foreach(usize slot; bitsSetRange(pointerBits, fromSlot, fromSlot + shiftedSlots)) {
				const u32 newOffset = ptrIndexToMemOffset(PointerId(cast(u32)slot), ptrSize);
				const u32 oldOffset = newOffset + byteOffset;
				AllocId val;
				assert(outRefs.remove(allocator, oldOffset, val));
				outRefs.put(allocator, newOffset, val);
			}
		}

		// copy init bits
		static if (SANITIZE_UNINITIALIZED_MEM) {
			usize* initBits = cast(usize*)&initBitmap.front();
			copyBitRange(initBits, initBits, fromByte, toByte, shiftedBytes);
		}

		// clean trailing init bits
		static if (SANITIZE_UNINITIALIZED_MEM) {
			markInitBits(fromByte + shiftedBytes, toByte - fromByte, false);
		}

		allocations.unput(to - from);

		if (allocations.length) {
			bytesUsed = allocations.back.offset + allocations.back.alignedSize;
		} else {
			bytesUsed = 0;
		}
	}

	static if (SANITIZE_UNINITIALIZED_MEM)
	usz countInitBits(usz offset, usz size) {
		usz* ptr = cast(usz*)&initBitmap.front();
		return popcntBitRange(ptr, offset, offset + size);
	}

	static if (SANITIZE_UNINITIALIZED_MEM)
	void markInitBits(usz offset, usz size, bool value) {
		if (size == 0) return;
		usz* ptr = cast(usz*)&initBitmap.front();
		setBitRange(ptr, offset, offset + size, value);
	}

	bool getInitBit(usz index) {
		usz* ptr = cast(usz*)&initBitmap.front();
		return getBitAt(ptr, index);
	}

	usz countPointerBits(PointerId offset, usz size) {
		usz* ptr = cast(usz*)&pointerBitmap.front();
		return popcntBitRange(ptr, offset, offset + size);
	}

	void markPointerBits(PointerId offset, usz size, bool value) {
		usz* ptr = cast(usz*)&pointerBitmap.front();
		setBitRange(ptr, offset, offset + size, value);
	}

	bool getPtrBit(PointerId index) {
		usz* ptr = cast(usz*)&pointerBitmap.front();
		return getBitAt(ptr, index);
	}

	void setPtrBit(PointerId index) {
		usz* ptr = cast(usz*)&pointerBitmap.front();
		setBitAt(ptr, index);
	}

	void resetPtrBit(PointerId index) {
		usz* ptr = cast(usz*)&pointerBitmap.front();
		resetBitAt(ptr, index);
	}
}

// Doesn't delete the heap allocations
void moveMemToStatic(
	ref VoxAllocator allocator,
	ref Memory static_mem,
	ref Memory heap_mem,
	AllocId root,
	PtrSize ptrSize)
{
	assert(root.kind == MemoryKind.static_mem, "Root must be in static memory");

	static void visit(
		ref VoxAllocator allocator,
		ref Memory static_mem,
		ref Memory heap_mem,
		AllocId node,
		PtrSize ptrSize) @nogc nothrow
	{
		assert(node.kind == MemoryKind.heap_mem, "Node must be in heap memory");
		Allocation* heap_alloc = &heap_mem.allocations[node.index];
		if (heap_alloc.isMarked) return;

		u32 perm = MemoryFlags.read | heap_alloc.isRuntimeWritable ? MemoryFlags.runtime_write : 0;
		AllocId static_node = static_mem.allocate(allocator, heap_alloc.sizeAlign, cast(MemoryFlags)perm);

		{
			Allocation* static_alloc = &static_mem.allocations[static_node.index];

			// Copy numInRefs to static, before markAsMovedToStaticMem
			static_alloc.numInRefs = heap_alloc.numInRefs;

			// Copy pointer bits
			usz* dstPtrBits = cast(usz*)&static_mem.pointerBitmap.front();
			usz* srcPtrBits = cast(usz*)&heap_mem.pointerBitmap.front();
			const PointerId dstPtrSlot  = memOffsetToPtrIndex(static_alloc.offset, ptrSize);
			const PointerId srcPtrSlot  = memOffsetToPtrIndex(heap_alloc.offset,   ptrSize);
			const PointerId numPtrSlots = memOffsetToPtrIndex(static_alloc.alignedSize, ptrSize);
			copyBitRange!usz(dstPtrBits, srcPtrBits, dstPtrSlot, srcPtrSlot, numPtrSlots);

			// Copy init bits
			static if (SANITIZE_UNINITIALIZED_MEM) {
				usz* dstInitBits = cast(usz*)&static_mem.initBitmap.front();
				usz* srcInitBits = cast(usz*)&heap_mem.initBitmap.front();
				copyBitRange(dstInitBits, srcInitBits, static_alloc.offset, heap_alloc.offset, static_alloc.alignedSize);
			}
		}

		// This will overwrite heap_alloc.numInRefs
		heap_alloc.markAsMovedToStaticMem(static_node);

		foreach(u32 offset, ref AllocId target; AllocationRefIterator(&heap_mem, *heap_alloc, ptrSize)) {
			if (target.kind != MemoryKind.heap_mem) {
				// just copy the pointer to new memory
				static if (OUT_REFS_PER_MEMORY) {
					// writefln("copy ref %s|%s to %s:%s", node, static_node, offset, target);
					Allocation* static_alloc = &static_mem.allocations[static_node.index];
					static_mem.outRefs.put(allocator, static_alloc.offset + offset, target);
				}
				continue;
			}

			// visit reallocates static_mem.outRefs, static_mem.allocations. Can't reuse static_alloc
			visit(allocator, static_mem, heap_mem, target, ptrSize);

			Allocation* static_alloc = &static_mem.allocations[static_node.index];
			Allocation* target_alloc = &heap_mem.allocations[target.index];

			// writefln("in %s|%s update %s:%s to %s:%s", node, static_node, offset, target, offset, target_alloc.getStaticMemIndex);
			static if (OUT_REFS_PER_ALLOCATION) {
				target = target_alloc.getStaticMemIndex;
			}
			static if (OUT_REFS_PER_MEMORY) {
				static_mem.outRefs.put(allocator, static_alloc.offset + offset, target_alloc.getStaticMemIndex);
			}
		}

		{
			Allocation* static_alloc = &static_mem.allocations[static_node.index];
			static if (OUT_REFS_PER_ALLOCATION) {
				static_alloc.outRefs = heap_alloc.outRefs;
				heap_alloc.outRefs = heap_alloc.outRefs.init;
			}
			static if (OUT_REFS_PER_MEMORY) {
				static_alloc.numOutRefs = heap_alloc.numOutRefs;
			}
		}
	}

	foreach(u32 offset, ref AllocId target; AllocationRefIterator(&static_mem, static_mem.allocations[root.index], ptrSize)) {
		if (target.kind != MemoryKind.heap_mem) continue;
		u32 target_index = target.index;
		// reallocates outRefs. `target` becomes invalid in OUT_REFS_PER_MEMORY case
		visit(allocator, static_mem, heap_mem, target, ptrSize);
		Allocation* target_alloc = &heap_mem.allocations[target_index];
		static if (OUT_REFS_PER_ALLOCATION) {
			target = target_alloc.getStaticMemIndex;
		}
		static if (OUT_REFS_PER_MEMORY) {
			Allocation* root_alloc = &static_mem.allocations[root.index];
			const u32 newOffset = root_alloc.offset + offset;
			static_mem.outRefs.put(allocator, newOffset, target_alloc.getStaticMemIndex);
		}
	}
}


struct AllocationRefIterator {
	@nogc nothrow:

	Memory* mem;
	Allocation alloc;
	// in bytes
	PtrSize ptrSize;

	i32 opApply(scope i32 delegate(u32 offset, ref AllocId target) @nogc nothrow del) {
		static if (OUT_REFS_PER_ALLOCATION) {
			foreach(const u32 k, ref AllocId v; alloc.outRefs) {
				if (i32 ret = del(k, v)) return ret;
			}
		} else {
			if (alloc.numOutRefs == 0) return 0;
			size_t* ptr = cast(size_t*)&mem.pointerBitmap.front();
			PointerId from = memOffsetToPtrIndex(alloc.offset, ptrSize);
			PointerId to   = memOffsetToPtrIndex(alloc.offset + alloc.alignedSize, ptrSize);
			foreach(size_t slot; bitsSetRange(ptr, from, to)) {
				u32 memOffset = ptrIndexToMemOffset(PointerId(cast(u32)slot), ptrSize);
				AllocId* val = memOffset in mem.outRefs;
				assert(val);
				assert(memOffset >= alloc.offset);
				u32 localOffset = memOffset - alloc.offset;
				if (i32 ret = del(localOffset, *val)) return ret;
			}
		}
		return 0;
	}
}

enum MemoryKind : u8 {
	// heap must be 0, because we reserve 0th allocation and null pointer is a heap pointer with all zeroes
	heap_mem,
	stack_mem,
	static_mem,
	func_id,
}

immutable string[4] memoryKindString = [
	"heap",
	"stack",
	"static",
	"function",
];

immutable string[4] memoryKindLetter = [
	"h", "s", "g", "f"
];

enum MemoryFlags : u8 {
	none          = 0,
	read          = 1 << 0,
	write         = 1 << 1,
	read_write    = read | write,
	runtime_write = 1 << 2,
	isFreed       = 1 << 3,
	isMarked      = 1 << 4,
}

u32 as_u32(PtrSize s) {
	pragma(inline, true);
	return s;
}

u32 inBytes(PtrSize s) {
	pragma(inline, true);
	return (s+1) * 4;
}

u32 inBits(PtrSize s) {
	pragma(inline, true);
	return (s+1) * 32;
}

PointerId memOffsetToPtrIndex(u32 offset, PtrSize ptrSize) {
	pragma(inline, true);
	assert((offset % ptrSize.inBytes) == 0);
	return PointerId(offset >> (ptrSize + 2));
}

u32 ptrIndexToMemOffset(PointerId ptr, PtrSize ptrSize) {
	pragma(inline, true);
	return ptr.index << (ptrSize + 2);
}
