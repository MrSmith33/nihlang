/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.memory;

import vox.lib;
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

struct Allocation {
	@nogc nothrow:

	// Start in parent Memory.memory
	// All allocations are aligned to 8 bytes in Memory buffer
	u32 offset;
	// Size in bytes
	u32 size;
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
}

struct Memory {
	@nogc nothrow:

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
	// How many bytes are used out of memory.reserved bytes
	u32 bytesUsed;

	void reserve(ref VoxAllocator allocator, u32 size, PtrSize ptrSize) {
		memory.voidPut(allocator, size);
		// By default no pointers are in memory
		u8[] data1 = pointerBitmap.voidPut(allocator, divCeil(size, ptrSize.inBits));
		data1[] = 0;
		static if (SANITIZE_UNINITIALIZED_MEM) {
			// By default all bytes are uninitialized
			u8[] data2 = initBitmap.voidPut(allocator, divCeil(size, 8));
			data2[] = 0;
		}
	}

	void clear(ref VoxAllocator allocator, PtrSize ptrSize) {
		static if (OUT_REFS_PER_ALLOCATION) {
			foreach(ref alloc; allocations) {
				alloc.outRefs.free(allocator);
			}
		} else {
			outRefs.clear;
		}
		static if (SANITIZE_UNINITIALIZED_MEM) {
			markInitBits(0, bytesUsed, false);
		}
		allocations.clear;
		bytesUsed = 0;
	}

	AllocId allocate(ref VoxAllocator allocator, SizeAndAlign sizeAlign, MemoryKind allocKind) {
		u32 index = allocations.length;
		u32 offset = bytesUsed;
		// allocate in multiple of 8 bytes
		// so that pointers are always aligned in memory and we can use pointer bitmap
		u32 alignedSize = alignValue(sizeAlign.size, 8);
		bytesUsed += alignedSize;
		if (bytesUsed >= memory.length) panic("Out of %s memory", memoryKindString[allocKind]);
		allocations.put(allocator, Allocation(offset, sizeAlign.size));
		return AllocId(index, allocKind);
	}

	// only for stack allocations
	// assumes all allocations to be in sequential order in memory
	// Doesn't clear outRefs or pointer bitmap
	void popAllocations(ref VoxAllocator allocator, u32 howMany) {
		assert(allocations.length >= howMany);
		allocations.unput(howMany);

		if (allocations.length) {
			u32 alignedSize = alignValue(allocations.back.size, 8);
			bytesUsed = allocations.back.offset + alignedSize;
		} else {
			bytesUsed = 0;
		}
	}

	static if (SANITIZE_UNINITIALIZED_MEM)
	void markInitBits(u32 offset, u32 size, bool value) {
		size_t* ptr = cast(size_t*)&initBitmap.front();
		setBitRange(ptr, offset, offset+size, value);
	}

	void setPtrBit(u32 offset) {
		size_t* ptr = cast(size_t*)&pointerBitmap.front();
		setBitAt(ptr, offset);
	}

	void resetPtrBit(u32 offset) {
		size_t* ptr = cast(size_t*)&pointerBitmap.front();
		resetBitAt(ptr, offset);
	}
}

struct AllocationRefIterator {
	@nogc nothrow:

	Memory* mem;
	Allocation* alloc;
	// in bytes
	PtrSize ptrSize;

	i32 opApply(scope i32 delegate(u32 offset, AllocId target) @nogc nothrow del) {
		static if (OUT_REFS_PER_ALLOCATION) {
			foreach(const u32 k, ref AllocId v; alloc.outRefs) {
				if (i32 ret = del(k, v)) return ret;
			}
		} else {
			if (alloc.numOutRefs == 0) return 0;
			size_t* ptr = cast(size_t*)&mem.pointerBitmap.front();
			u32 alignedSize = alignValue(alloc.size, 8);
			u32 from = memOffsetToPtrIndex(alloc.offset, ptrSize);
			u32 to   = memOffsetToPtrIndex(alloc.offset + alignedSize, ptrSize);
			foreach(size_t slot; bitsSetRange(ptr, from, to)) {
				u32 memOffset = ptrIndexToMemOffset(cast(u32)slot, ptrSize);
				AllocId val = mem.outRefs.get(memOffset);
				assert(val.isDefined);
				u32 localOffset = memOffset - alloc.offset;
				if (i32 ret = del(localOffset, val)) return ret;
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

enum PtrSize : u8 {
	_32 = 0,
	_64 = 1,
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

u32 memOffsetToPtrIndex(u32 offset, PtrSize ptrSize) {
	pragma(inline, true);
	return offset >> (ptrSize + 2);
}

u32 ptrIndexToMemOffset(u32 val, PtrSize ptrSize) {
	pragma(inline, true);
	return val << (ptrSize + 2);
}
