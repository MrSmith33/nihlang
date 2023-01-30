/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.memory;

import vox.lib;

@nogc nothrow:

enum MEMORY_RELOCATIONS_PER_ALLOCATION = true;
enum MEMORY_RELOCATIONS_PER_MEMORY = !MEMORY_RELOCATIONS_PER_ALLOCATION;

struct AllocId {
	@nogc nothrow:
	this(u32 index, u32 generation, MemoryKind kind) {
		this.payload = (index & ((1 << 30) - 1)) | (kind << 30);
	}

	private u32 payload;

	u32 index() const {
		return cast(u32)(payload & ((1 << 30) - 1));
	}

	// kind: heap, static, function, stack
	MemoryKind kind() const {
		return cast(MemoryKind)(payload >> 30);
	}

	bool isDefined() const { return payload != 0; }
	bool isUndefined() const { return payload == 0; }
}

struct Allocation {
	u32 offset;
	u32 size;
	static if (MEMORY_RELOCATIONS_PER_ALLOCATION) {
		HashMap!(u32, AllocId, u32.max) relocations;
	}
}

struct Memory {
	@nogc nothrow:

	Array!Allocation allocations;
	Array!u8 memory;
	Array!u8 pointerBitmap;
	static if (MEMORY_RELOCATIONS_PER_MEMORY) {
		HashMap!(u32, AllocId, u32.max) relocations;
	}
	u32 bytesUsed;

	// ptrSize is 4 or 8
	void reserve(ref VoxAllocator allocator, u32 size, u32 ptrSize) {
		assert(ptrSize == 4 || ptrSize == 8, "Invalid ptr size");
		memory.voidPut(allocator, size);
		// 1 bit per pointer slot
		// pointers must be aligned in memory
		// each allocation is aligned at least to a pointer size
		pointerBitmap.voidPut(allocator, size / (ptrSize * 8));
	}

	void clear(ref VoxAllocator allocator) {
		static if (MEMORY_RELOCATIONS_PER_MEMORY) {
			relocations.clear;
		} else {
			foreach(ref alloc; allocations)
				alloc.relocations.free(allocator);
		}
		allocations.clear;
		bytesUsed = 0;
	}

	AllocId allocate(ref VoxAllocator allocator, SizeAndAlign sizeAlign, MemoryKind allocKind) {
		u32 index = allocations.length;
		u32 offset = bytesUsed;
		bytesUsed += sizeAlign.size;
		if (bytesUsed >= memory.length) panic("Out of %s memory", memoryKindString[allocKind]);
		allocations.put(allocator, Allocation(offset, sizeAlign.size));
		u32 generation = 0;
		return AllocId(index, generation, allocKind);
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

// Low 4 bits are for reading, high 4 bits are for writing
// Bit position is eaual to MemoryKind
enum MemFlags : u8 {
	heap_R    = 0b_0000_0001,
	stack_R   = 0b_0000_0010,
	static_R  = 0b_0000_0100,

	heap_W    = 0b_0001_0000,
	stack_W   = 0b_0010_0000,
	static_W  = 0b_0100_0000,

	heap_RW   = 0b_0001_0001,
	stack_RW  = 0b_0010_0010,
	static_RW = 0b_0100_0100,
}
