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
		static if (SANITIZE_UNINITIALIZED_MEM) {
			markInitBits(0, bytesUsed, false);
		}
		allocations.clear;
		bytesUsed = 0;
	}

	AllocId allocate(ref VoxAllocator allocator, SizeAndAlign sizeAlign, MemoryFlags perm) {
		u32 index = allocations.length;
		u32 offset = bytesUsed;
		// allocate in multiple of ALLOCATION_GRANULARITY bytes
		// so that pointers are always aligned in memory and we can use pointer bitmap
		bytesUsed += alignValue(sizeAlign.size, Allocation.ALLOCATION_GRANULARITY);
		if (bytesUsed >= memory.length) panic("Out of %s memory", memoryKindString[kind]);
		allocations.put(allocator, Allocation(offset, sizeAlign, perm));
		return AllocId(index, kind);
	}

	// only for stack allocations
	// assumes all allocations to be in sequential order in memory
	// Doesn't clear outRefs or pointer bitmap
	void popAllocations(ref VoxAllocator allocator, u32 howMany) {
		assert(allocations.length >= howMany);
		allocations.unput(howMany);

		if (allocations.length) {
			bytesUsed = allocations.back.offset + allocations.back.alignedSize;
		} else {
			bytesUsed = 0;
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

		usize* pointerBits = cast(usize*)&pointerBitmap.front();
		const PointerId fromSlot = memOffsetToPtrIndex(fromByte, ptrSize);
		const PointerId toSlot   = memOffsetToPtrIndex(toByte, ptrSize);
		const PointerId lastSlot = memOffsetToPtrIndex(lastByte, ptrSize);
		const u32 shiftedSlots   = lastSlot - toSlot;

		// check that all pointers were removed
		static if (SLOW_CHECKS) {
			assert(popcntBitRange(pointerBits, fromSlot, toSlot) == 0);
		}

		// copy pointer bits
		copyBitRange(pointerBits, pointerBits, fromSlot, toSlot, shiftedSlots);

		// update outRefs in shifted allocations
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

		if (allocations.length) {
			bytesUsed = allocations.back.offset + allocations.back.alignedSize;
		} else {
			bytesUsed = 0;
		}
	}

	static if (SANITIZE_UNINITIALIZED_MEM)
	void markInitBits(u32 offset, u32 size, bool value) {
		size_t* ptr = cast(size_t*)&initBitmap.front();
		setBitRange(ptr, offset, offset+size, value);
	}

	void setPtrBit(PointerId index) {
		size_t* ptr = cast(size_t*)&pointerBitmap.front();
		setBitAt(ptr, index);
	}

	void resetPtrBit(PointerId index) {
		size_t* ptr = cast(size_t*)&pointerBitmap.front();
		resetBitAt(ptr, index);
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
			PointerId from = memOffsetToPtrIndex(alloc.offset, ptrSize);
			PointerId to   = memOffsetToPtrIndex(alloc.offset + alignedSize, ptrSize);
			foreach(size_t slot; bitsSetRange(ptr, from, to)) {
				u32 memOffset = ptrIndexToMemOffset(PointerId(cast(u32)slot), ptrSize);
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

enum MemoryFlags : u8 {
	none          = 0,
	read          = 1 << 0,
	write         = 1 << 1,
	read_write    = read | write,
	runtime_write = 1 << 2,
	isFreed       = 1 << 3,
	isMarked      = 1 << 4,
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

PointerId memOffsetToPtrIndex(u32 offset, PtrSize ptrSize) {
	pragma(inline, true);
	return PointerId(offset >> (ptrSize + 2));
}

u32 ptrIndexToMemOffset(PointerId ptr, PtrSize ptrSize) {
	pragma(inline, true);
	return ptr.index << (ptrSize + 2);
}
