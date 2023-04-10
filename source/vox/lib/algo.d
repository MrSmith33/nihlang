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

version(VANILLA_D) {
	public import core.stdc.string : memmove;
}

version(NO_DEPS) version (LDC) {
	public import core.stdc.string : memmove;
}

version(NO_DEPS) version(DigitalMars)
extern(C) void memmove(void* dst, const(void)* src, size_t len)
{
	version (LDC) {
		import ldc.intrinsics : llvm_memmove;
		llvm_memmove!size_t(dst, src, len);
	} else {
		if (src < dst) {
			if (src + len <= dst) {
				dst[0..len] = src[0..len];
			} else {
				for (size_t size = len; size > 0; --size) {
					*cast(ubyte*)(dst+size-1) = *cast(ubyte*)(src+size-1);
				}
			}
		} else if (src > dst) {
			if (dst + len <= src) {
				dst[0..len] = src[0..len];
			} else {
				for (size_t size = len; size > 0; --size) {
					*cast(ubyte*)dst++ = *cast(ubyte*)src++;
				}
			}
		} else {
			// noop
		}
	}
}

version(FUZZER){}else
version(NO_DEPS)
extern(C) int memcmp(const(void)* buf1, const(void)* buf2, size_t len) {
	if(!len) return 0;
	while(--len && *cast(ubyte*)buf1 == *cast(ubyte*)buf2) {
		++buf1;
		++buf2;
	}
	return *cast(ubyte*)buf1 - *cast(ubyte*)buf2;
}

/*void testMemmove() {
	ubyte[8] buf;

	buf = [1,2,3,4,5,6,7,8];
	memmove(&buf[4], &buf[0], 4);
	assert(buf == [1,2,3,4,1,2,3,4]);

	buf = [1,2,3,4,5,6,7,8];
	memmove(&buf[2], &buf[0], 6);
	assert(buf == [1,2,1,2,3,4,5,6]);

	buf = [1,2,3,4,5,6,7,8];
	memmove(&buf[0], &buf[0], 8);
	assert(buf == [1,2,3,4,5,6,7,8]);

	buf = [1,2,3,4,5,6,7,8];
	memmove(&buf[0], &buf[2], 6);
	assert(buf == [3,4,5,6,7,8,7,8]);

	buf = [1,2,3,4,5,6,7,8];
	memmove(&buf[0], &buf[4], 4);
	assert(buf == [5,6,7,8,5,6,7,8]);
}
*/


pragma(inline, true)
bool getBitAt(size_t* ptr, size_t bitIndex) {
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
int popcnt(size_t x) pure {
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
