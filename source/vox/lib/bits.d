/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.bits;

import vox.lib;

@nogc nothrow:

debug import vox.lib.bitcopy_test : printTestCase;

// Bit level memmove
// Handles overlapping dst and src ranges
void copyBitRange(T)(T* ptr, usize dst, usize src, usize length) {
	if (dst == src)  return;
	if (length == 0) return;

	enum BITS_PER_SLOT = T.sizeof * 8;

	isize srcFirstSlot = cast(isize) src / 8;
	isize srcFirstBit  = cast(isize) src % 8;
	isize srcLastSlot  = cast(isize)(src + length - 1) / 8;
	isize srcLastBit   = cast(isize)(src + length - 1) % 8;

	isize dstFirstSlot = cast(isize) dst / 8;
	isize dstFirstBit  = cast(isize) dst % 8;
	isize dstLastSlot  = cast(isize)(dst + length - 1) / 8;
	isize dstLastBit   = cast(isize)(dst + length - 1) % 8;

	ref T atSrc(isize index) { pragma(inline, true);
		debug if (index < srcFirstSlot || index > srcLastSlot) {
			writefln("index (%s) >= srcFirstSlot (%s) && index (%s) <= srcLastSlot (%s)", index, srcFirstSlot, index, srcLastSlot);
			printTestCase(*cast(u64*)ptr, dst, src, length);
			assert(false);
		}
		return ptr[index];
	}

	ref T atDst(isize index) { pragma(inline, true);
		debug if (index < dstFirstSlot || index > dstLastSlot) {
			writefln("index (%s) >= dstFirstSlot (%s) && index (%s) <= dstLastSlot (%s)", index, dstFirstSlot, index, dstLastSlot);
			printTestCase(*cast(u64*)ptr, dst, src, length);
			assert(false);
		}
		return ptr[index];
	}

	static T mergeSlots(const usize bitDeficit, const T lowSlot, const T highSlot) {
		pragma(inline, true);
		const T lowData  = lowSlot.shiftDown(bitDeficit);
		const T highData = highSlot.shiftUp(BITS_PER_SLOT - bitDeficit);
		const T srcData  = lowData | highData;
		return srcData;
	}

	const usize bitDeficit = (srcFirstBit - dstFirstBit) & (BITS_PER_SLOT-1);

	if (dstFirstSlot == dstLastSlot) { // single dst slot, 1 or 2 src slots
		const T srcLow          = atSrc(srcFirstSlot);
		const T srcHigh         = atSrc(srcLastSlot);
		const T srcData         = mergeSlots(bitDeficit, srcLow, srcHigh);
		const T dstStartBitMask = lowMask!T(dstFirstBit);
		const T dstEndBitMask   = lowMask!T(dstLastBit+1);
		const T combineMask     = ~dstStartBitMask & dstEndBitMask;
		const T origData        = atDst(dstFirstSlot) & ~combineMask;
		atDst(dstFirstSlot)     = origData | srcData & combineMask;
		return;
	}

	if (srcFirstSlot == srcLastSlot) { // 2 dst slots, 1 src slot
		const T srcSlot        = atSrc(srcFirstSlot);
		const T srcData        = rotateDown(srcSlot, bitDeficit);
		const T origData0      = atDst(dstFirstSlot+0);
		const T origData1      = atDst(dstFirstSlot+1);
		atDst(dstFirstSlot+0)  = combineBits(origData0, srcData, dstFirstBit);
		atDst(dstFirstSlot+1)  = combineBits(srcData, origData1, dstLastBit+1);
		return;
	}

	// below, both dst and src are at least 2 slots in size
	if (dst < src && srcFirstBit == dstFirstBit) { // direct copy
		atDst(dstFirstSlot) = combineBits(atDst(dstFirstSlot), atSrc(srcFirstSlot), dstFirstBit);
		foreach (i; 1..dstLastSlot - dstFirstSlot) {
			atDst(dstFirstSlot+i) = atSrc(srcFirstSlot+i);
		}
		atDst(dstLastSlot) = combineBits(atSrc(srcLastSlot), atDst(dstLastSlot), dstLastBit+1);
		return;
	}

	if (dst < src) {
		const usize srcSlotIndex  = srcFirstSlot + (srcFirstBit > dstFirstBit);
		T srcLow  = atSrc(srcFirstSlot);
		T srcHigh = atSrc(srcSlotIndex);
		{	// first dst slot
			const T srcData       = mergeSlots(bitDeficit, srcLow, srcHigh);
			const T origData      = atDst(dstFirstSlot);
			atDst(dstFirstSlot)   = combineBits(origData, srcData, dstFirstBit);
		}
		foreach (i; 1..dstLastSlot - dstFirstSlot) { // full dst slots
			srcLow  = srcHigh;
			srcHigh = atSrc(srcSlotIndex+i);
			const T srcData       = mergeSlots(bitDeficit, srcLow, srcHigh);
			atDst(dstFirstSlot+i) = srcData;
		}
		{	// last slot
			srcLow  = srcHigh;
			srcHigh = atSrc(srcLastSlot);
			const T srcData       = mergeSlots(bitDeficit, srcLow, srcHigh);
			const T origData      = atDst(dstLastSlot);
			atDst(dstLastSlot)    = combineBits(srcData, origData, dstLastBit+1);
		}
		return;
	}

	if (dst > src && srcFirstBit == dstFirstBit) {
		atDst(dstLastSlot)  = combineBits(atSrc(srcLastSlot), atDst(dstLastSlot), dstLastBit+1);
		foreach (i; 1..dstLastSlot - dstFirstSlot) {
			atDst(dstLastSlot-i) = atSrc(srcLastSlot-i);
		}
		atDst(dstFirstSlot) = combineBits(atDst(dstFirstSlot), atSrc(srcFirstSlot), dstFirstBit);
		return;
	}

	if (dst > src) {
		const usize srcSlotIndex  = srcLastSlot - (srcLastBit < dstLastBit);
		T srcHigh = atSrc(srcLastSlot);
		T srcLow  = atSrc(srcSlotIndex);
		{	// last dst slot
			const T srcData       = mergeSlots(bitDeficit, srcLow, srcHigh);
			const T origData      = atDst(dstLastSlot);
			atDst(dstLastSlot)    = combineBits(srcData, origData, dstLastBit + 1);
		}
		foreach (i; 1..dstLastSlot - dstFirstSlot) { // full dst slots
			srcHigh = srcLow;
			srcLow  = atSrc(srcSlotIndex-i);
			const T srcData       = mergeSlots(bitDeficit, srcLow, srcHigh);
			atDst(dstLastSlot-i)  = srcData;
		}
		{	// first dst slot
			srcHigh = srcLow;
			srcLow  = atSrc(srcFirstSlot);
			const T srcData       = mergeSlots(bitDeficit, srcLow, srcHigh);
			const T origData      = atDst(dstFirstSlot);
			atDst(dstFirstSlot)   = combineBits(origData, srcData, dstFirstBit);
		}
		return;
	}
}

// numLowBits = 5
// low   LLLLLXXX
// high  XXXXXHHH
// res   LLLLLHHH
T combineBits(T)(T lowBits, T highBits, usize numLowBits) {
	pragma(inline, true);
	const T lowBitMask = cast(T)((T(1) << numLowBits) - 1);
	return cast(T)((lowBits & lowBitMask) | (highBits & ~lowBitMask));
}

T rotateDown(T)(T val, usize numBits) {
	pragma(inline, true);
	return ror!T(val, cast(u32)numBits);
}

T rotateUp(T)(T val, usize numBits) {
	pragma(inline, true);
	return rol!T(val, cast(u32)numBits);
}

T shiftDown(T)(T val, usize numBits) {
	pragma(inline, true);
	if (numBits >= (T.sizeof*8)) return 0;
	// assert((val >>> numBits) == val >>> (numBits & (T.sizeof*8-1)));
	return cast(T)(val >>> (numBits & (T.sizeof*8-1)));
}

T shiftUp(T)(T val, usize numBits) {
	pragma(inline, true);
	if (numBits >= (T.sizeof*8)) return 0;
	return cast(T)(val << (numBits & (T.sizeof*8-1)));
}

T lowMask(T)(usize numBits) {
	pragma(inline, true);
	return cast(T)((T(1) << numBits) - 1);
}

T highMask(T)(usize numBits) {
	pragma(inline, true);
	return ~cast(T)((T(1) << (T.sizeof*8 - numBits)) - 1);
}

void printMarker(usize padding, usize from, usize length, char marker) {
	foreach(_; 0..padding + from + from/8) write(' ');
	foreach(i; 0..length) {
		write(marker);
		if (i+1 < length && (from+i+1)%8 == 0) write(' ');
	}
	writeln;
}

void printBitsln(const(void)* ptr, usize from, usize to) {
	printBits(ptr, from, to);
	writeln;
}
void printBits(const(void)* ptr, usize from, usize to) {
	foreach(index; from..to) {
		bool bit = getBitAt(cast(usize*)ptr, index);
		write(cast(char)('0' + bit));
		if (index+1 < to && (index+1)%8 == 0) write(' ');
	}
}

void printBits(T)(T val) {
	printBits(&val, 0, T.sizeof * 8);
}
void printBitsln(T)(T val) {
	printBits(&val, 0, T.sizeof * 8);
	writeln;
}

T reverse_bits(T)(T b) {
	static if (T.sizeof >= 8) {
		T mask64 = 0xFFFF_FFFF_0000_0000UL;
		b = (b & mask64) >> 32 | (b & ~mask64) << 32;
	}
	static if (T.sizeof >= 4) {
		T mask32 = 0b1111111111111111000000000000000011111111111111110000000000000000UL;
		b = (b & mask32) >> 16 | (b & ~mask32) << 16;
	}
	static if (T.sizeof >= 2) {
		T mask16 = 0b1111111100000000111111110000000011111111000000001111111100000000UL;
		b = (b & mask16) >> 8 | (b & ~mask16) << 8;
	}
	T mask8 = 0b1111000011110000111100001111000011110000111100001111000011110000UL;
	b = (b & mask8) >> 4 | (b & ~mask8) << 4;
	T mask4 = 0b1100110011001100110011001100110011001100110011001100110011001100UL;
	b = (b & mask4) >> 2 | (b & ~mask4) << 2;
	T mask2 = 0b1010101010101010101010101010101010101010101010101010101010101010UL;
	b = (b & mask2) >> 1 | (b & ~mask2) << 1;
	return b;
}
