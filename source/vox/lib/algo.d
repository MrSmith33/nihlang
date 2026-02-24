/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.algo;

import vox.lib;

@nogc nothrow:


void swap(T)(ref T lhs, ref T rhs) pure {
	auto tmp = lhs;
	lhs = rhs;
	rhs = tmp;
}

T[n] staticArray(T, size_t n)(T[n] a) { return a; }

pragma(inline, true)
bool getBitAt(const(size_t)* ptr, size_t bitIndex) {
	static if (size_t.sizeof == 8)
		return ((ptr[bitIndex >> 6] & (1L << (bitIndex & 63)))) != 0;
	else
		return ((ptr[bitIndex >> 5] & (1L << (bitIndex & 31)))) != 0;
}

version(LDC)
pragma(LDC_intrinsic, "ldc.bitop.bts")
int setBitAt(size_t* p, size_t bitnum);

version (DigitalMars)
int setBitAt(size_t* p, size_t bitnum) pure {
	size_t slotIndex = bitnum / (size_t.sizeof * 8);
	size_t bitmask = size_t(1) << (bitnum & ((size_t.sizeof * 8) - 1));
	size_t originalSlot = p[slotIndex];
	p[slotIndex] = originalSlot | bitmask;
	return (originalSlot & bitmask) > 0;
}

version(LDC)
pragma(LDC_intrinsic, "llvm.ctlz.i#")
private T llvm_ctlz(T)(T src, bool isZeroUndefined) pure if (__traits(isIntegral, T));

T clz(T)(T val) pure {
	version(LDC) {
		return llvm_ctlz!T(val, false);
	} else {
		if (val == 0) return T.sizeof * 8;
		return cast(T)(T.sizeof * 8 - 1 - bsr(val));
	}
}

version(LDC)
pragma(LDC_intrinsic, "llvm.cttz.i#")
private T llvm_cttz(T)(T src, bool isZeroUndefined) pure if (__traits(isIntegral, T));

T ctz(T)(T val) pure {
	version(LDC) {
		return llvm_cttz!T(val, false);
	} else {
		if (val == 0) return T.sizeof * 8;
		return cast(T)bsf(val);
	}
}


version(LDC)
pragma(LDC_intrinsic, "ldc.bitop.btc")
int toggleBitAt(size_t* p, size_t bitnum) pure;

version (DigitalMars)
int toggleBitAt(size_t* p, size_t bitnum) pure @system {
	size_t slotIndex = bitnum / (size_t.sizeof * 8);
	size_t bitmask = size_t(1) << (bitnum & ((size_t.sizeof * 8) - 1));
	size_t originalSlot = p[slotIndex];
	p[slotIndex] = originalSlot ^ bitmask;
	return (originalSlot & bitmask) > 0;
}


version(LDC)
pragma(LDC_intrinsic, "ldc.bitop.btr")
int resetBitAt(size_t* p, size_t bitnum) pure;

version (DigitalMars)
int resetBitAt(size_t* p, size_t bitnum) pure @system {
	size_t slotIndex = bitnum / (size_t.sizeof * 8);
	size_t bitmask = size_t(1) << (bitnum & ((size_t.sizeof * 8) - 1));
	size_t originalSlot = p[slotIndex];
	p[slotIndex] = originalSlot & ~bitmask;
	return (originalSlot & bitmask) > 0;
}


version(LDC)
pragma(LDC_intrinsic, "llvm.ctpop.i#")
T _popcnt(T)(T src) pure if (__traits(isIntegral, T));

version (DigitalMars) {
	import core.bitop : _popcnt;
}

pragma(inline, true)
int popcnt(u64 x) pure {
	return cast(int)_popcnt(x);
}

// end is exclusive
void setBitRange(size_t* ptr, size_t from, size_t to, bool val) {
	enum BITS_PER_SLOT = size_t.sizeof * 8;

	size_t fromBit  = from % BITS_PER_SLOT;
	size_t toBit    =   to % BITS_PER_SLOT;

	size_t fromSlot = from / BITS_PER_SLOT;
	size_t toSlot   =   to / BITS_PER_SLOT;

	// All bits are in the same size_t slot
	if (fromSlot == toSlot) {
		size_t fromSlotMask = ~((size_t(1) << fromBit) - 1);
		size_t toSlotMask =    (size_t(1) << toBit) - 1;
		size_t mask = fromSlotMask & toSlotMask;

		if (val) ptr[fromSlot] |= mask;
		else     ptr[fromSlot] &= ~mask;
		return;
	}

	// Incomplete slot at the beginning
	if (fromBit != 0) {
		size_t fromSlotMask = ~((size_t(1) << fromBit) - 1);
		if (val) ptr[fromSlot] |=  fromSlotMask;
		else     ptr[fromSlot] &= ~fromSlotMask;
		++fromSlot;
	}

	// Range of full slots can be filled faster
	ptr[fromSlot .. toSlot] = 0 - cast(size_t)val;

	// Incomplete slot at the end
	if (toBit != 0) {
		size_t toSlotMask = (size_t(1) << toBit) - 1;
		if (val) ptr[toSlot] |=  toSlotMask;
		else     ptr[toSlot] &= ~toSlotMask;
	}
}

// counts set bits in a range of bits
size_t popcntBitRange(size_t* ptr, size_t from, size_t to) {
	assert(from <= to);
	enum BITS_PER_SLOT = size_t.sizeof * 8;

	size_t fromBit  = from % BITS_PER_SLOT;
	size_t toBit    =   to % BITS_PER_SLOT;

	size_t fromSlot = from / BITS_PER_SLOT;
	size_t toSlot   =   to / BITS_PER_SLOT;

	// All bits are in the same size_t slot
	if (fromSlot == toSlot) {
		size_t fromSlotMask = ~((size_t(1) << fromBit) - 1);
		size_t toSlotMask =    (size_t(1) << toBit) - 1;
		size_t mask = fromSlotMask & toSlotMask;

		return popcnt(ptr[fromSlot] & mask);
	}

	size_t count = 0;

	// Incomplete slot at the beginning
	if (fromBit != 0) {
		size_t fromSlotMask = ~((size_t(1) << fromBit) - 1);
		count = popcnt(ptr[fromSlot] & fromSlotMask);
		++fromSlot;
	}

	// Range of full slots can be counted faster
	foreach(size_t slot; ptr[fromSlot .. toSlot]) {
		count += popcnt(slot);
	}

	// Incomplete slot at the end
	if (toBit != 0) {
		size_t toSlotMask = (size_t(1) << toBit) - 1;
		count += popcnt(ptr[toSlot] & toSlotMask);
	}

	return count;
}

// popcntBitRange != 0
bool isEmptyBitRange(size_t* ptr, size_t from, size_t to) {
	assert(from <= to);
	enum BITS_PER_SLOT = size_t.sizeof * 8;

	size_t fromBit  = from % BITS_PER_SLOT;
	size_t toBit    =   to % BITS_PER_SLOT;

	size_t fromSlot = from / BITS_PER_SLOT;
	size_t toSlot   =   to / BITS_PER_SLOT;

	// All bits are in the same size_t slot
	if (fromSlot == toSlot) {
		size_t fromSlotMask = ~((size_t(1) << fromBit) - 1);
		size_t toSlotMask =    (size_t(1) << toBit) - 1;
		size_t mask = fromSlotMask & toSlotMask;

		return (ptr[fromSlot] & mask) != 0;
	}

	// Incomplete slot at the beginning
	if (fromBit != 0) {
		size_t fromSlotMask = ~((size_t(1) << fromBit) - 1);
		if ((ptr[fromSlot] & fromSlotMask) != 0) return true;
		++fromSlot;
	}

	// Range of full slots can be counted faster
	foreach(size_t slot; ptr[fromSlot .. toSlot]) {
		if (slot != 0) return true;
	}

	// Incomplete slot at the end
	if (toBit != 0) {
		size_t toSlotMask = (size_t(1) << toBit) - 1;
		if ((ptr[toSlot] & toSlotMask) != 0) return true;
	}

	return false;
}


// Most efficient with ulong
// Iterates all set bits in increasing order
BitsSet!T bitsSet(T)(T[] bitmap) { return BitsSet!T(bitmap); }

struct BitsSet(T)
{
	@nogc nothrow:

	T[] bitmap;

	int opApply(scope int delegate(size_t) @nogc nothrow dg)
	{
		foreach (size_t slotIndex, T slotBits; bitmap)
		{
			while (slotBits != 0)
			{
				// Extract lowest set isolated bit
				// 111000 -> 001000; 0 -> 0
				T lowestSetBit = slotBits & -slotBits;

				size_t lowestSetBitIndex = bsf(slotBits);
				if (int res = dg(slotIndex * T.sizeof * 8 + lowestSetBitIndex)) return res;

				// Disable lowest set isolated bit
				// 111000 -> 110000
				slotBits ^= lowestSetBit;
			}
		}

		return 0;
	}
}

BitsSetRange!T bitsSetRange(T)(T* bitmap, u32 from, u32 to) { return BitsSetRange!T(bitmap, from, to); }
struct BitsSetRange(T) {
	@nogc nothrow:

	T* ptr;
	u32 from;
	u32 to;

	import core.bitop : bsf;

	int opApply(scope int delegate(size_t) @nogc nothrow dg) {
		enum BITS_PER_SLOT = T.sizeof * 8;

		size_t fromBit  = from % BITS_PER_SLOT;
		size_t toBit    =   to % BITS_PER_SLOT;

		size_t fromSlot = from / BITS_PER_SLOT;
		size_t toSlot   =   to / BITS_PER_SLOT;

		// All bits are in the same size_t slot
		if (fromSlot == toSlot) {
			size_t fromSlotMask = ~((size_t(1) << fromBit) - 1);
			size_t toSlotMask =    (size_t(1) << toBit) - 1;
			size_t mask = fromSlotMask & toSlotMask;
			T slotBits = ptr[fromSlot] & mask;
			while (slotBits != 0) {
				T lowestSetBit = slotBits & -slotBits;
				if (int res = dg(fromSlot * BITS_PER_SLOT + bsf(slotBits))) return res;
				slotBits ^= lowestSetBit;
			}
			return 0;
		}

		// Incomplete slot at the beginning
		if (fromBit != 0) {
			size_t fromSlotMask = ~((size_t(1) << fromBit) - 1);
			T slotBits = ptr[fromSlot] & fromSlotMask;
			while (slotBits != 0) {
				T lowestSetBit = slotBits & -slotBits;
				if (int res = dg(fromSlot * BITS_PER_SLOT + bsf(slotBits))) return res;
				slotBits ^= lowestSetBit;
			}
			++fromSlot;
		}

		// Range of full slots can be counted faster
		foreach(i, T slotBits; ptr[fromSlot .. toSlot]) {
			size_t baseIndex = (fromSlot + i) * BITS_PER_SLOT;
			while (slotBits != 0) {
				T lowestSetBit = slotBits & -slotBits;
				if (int res = dg(baseIndex + bsf(slotBits))) return res;
				slotBits ^= lowestSetBit;
			}
		}

		// Incomplete slot at the end
		if (toBit != 0) {
			size_t toSlotMask = (size_t(1) << toBit) - 1;
			T slotBits = ptr[toSlot] & toSlotMask;
			while (slotBits != 0) {
				T lowestSetBit = slotBits & -slotBits;
				if (int res = dg(toSlot * BITS_PER_SLOT + bsf(slotBits))) return res;
				slotBits ^= lowestSetBit;
			}
		}

		return 0;
	}
}

BitsSetRangeReverse!T bitsSetRangeReverse(T)(T* bitmap, u32 from, u32 to) { return BitsSetRangeReverse!T(bitmap, from, to); }
struct BitsSetRangeReverse(T) {
	@nogc nothrow:

	T* ptr;
	u32 from;
	u32 to;

	import core.bitop : bsf;

	int opApply(scope int delegate(size_t) @nogc nothrow dg) {
		enum BITS_PER_SLOT = T.sizeof * 8;

		size_t fromBit  = from % BITS_PER_SLOT;
		size_t toBit    =   to % BITS_PER_SLOT;

		size_t fromSlot = from / BITS_PER_SLOT;
		size_t toSlot   =   to / BITS_PER_SLOT;

		// All bits are in the same size_t slot
		if (fromSlot == toSlot) {
			size_t fromSlotMask = ~((size_t(1) << fromBit) - 1);
			size_t toSlotMask =    (size_t(1) << toBit) - 1;
			size_t mask = fromSlotMask & toSlotMask;
			T slotBits = ptr[fromSlot] & mask;
			while (slotBits != 0) {
				size_t highestSetBitIndex = bsr(slotBits);
				if (int res = dg(fromSlot * BITS_PER_SLOT + highestSetBitIndex)) return res;
				slotBits ^= 1 << highestSetBitIndex;
			}
			return 0;
		}

		// Incomplete slot at the end
		if (toBit != 0) {
			size_t toSlotMask = (size_t(1) << toBit) - 1;
			T slotBits = ptr[toSlot] & toSlotMask;
			while (slotBits != 0) {
				size_t highestSetBitIndex = bsr(slotBits);
				if (int res = dg(toSlot * BITS_PER_SLOT + highestSetBitIndex)) return res;
				slotBits ^= 1 << highestSetBitIndex;
			}
		}

		// Range of full slots can be counted faster
		foreach_reverse(i, T slotBits; ptr[fromSlot .. toSlot]) {
			size_t baseIndex = (fromSlot + i) * BITS_PER_SLOT;
			while (slotBits != 0) {
				size_t highestSetBitIndex = bsr(slotBits);
				if (int res = dg(baseIndex + highestSetBitIndex)) return res;
				slotBits ^= 1 << highestSetBitIndex;
			}
		}

		// Incomplete slot at the beginning
		if (fromBit != 0) {
			size_t fromSlotMask = ~((size_t(1) << fromBit) - 1);
			T slotBits = ptr[fromSlot] & fromSlotMask;
			while (slotBits != 0) {
				size_t highestSetBitIndex = bsr(slotBits);
				if (int res = dg(fromSlot * BITS_PER_SLOT + highestSetBitIndex)) return res;
				slotBits ^= 1 << highestSetBitIndex;
			}
			++fromSlot;
		}

		return 0;
	}
}

bool startsWith(const(char)[] what, const(char)[] withWhat) {
	if (withWhat.length > what.length) return false;
	return what[0..withWhat.length] == withWhat;
}
