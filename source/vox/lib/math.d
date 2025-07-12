/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.math;

public import core.bitop : bsr, bsf, ror, rol;
import vox.lib;

@nogc nothrow:

T min(T)(T a, T b) pure {
	if (a < b) return a;
	return b;
}

T max(T)(T a, T b) pure {
	if (a > b) return a;
	return b;
}

T clamp(T)(T x, T min, T max) pure {
	if (x < min) return min;
	if (x > max) return max;
	return x;
}

T abs(T)(T a) pure {
	if (a < 0) return -a;
	return a;
}

i64 round(f64 x) pure {
	if (x < 0) return cast(i64)(x - 0.5);
	return cast(i64)(x + 0.5);
}

i32 signum(T)(const T x) pure {
	return (x > 0) - (x < 0);
}

T divCeil(T)(T a, T b) pure {
	return a / b + (a % b > 0);
}

T divFloor(T)(T a, T b) pure {
	return a / b - (a % b < 0);
}

T divNear(T)(T a, T b) pure {
	if ((a<0) != (b<0)) {
		return (a - b / 2) / b;
	}
	return (a + b / 2) / b;
}

// For b = 3
// a -6 -5 -4 -3 -2 -1 0 1 2 3 4 5 6
// r  0  1  2  0  1  2 0 1 2 0 1 2 0
T modEuclidean(T)(T a, T b) pure {
	T r = a % b;
	if (r < 0) return r + b;
	return r;
}

T nextPOT(T)(T x) pure {
	--x;
	x |= x >> 1;  // handle 2 bit numbers
	x |= x >> 2;  // handle 4 bit numbers
	x |= x >> 4;  // handle 8 bit numbers
	static if (T.sizeof >= 2) x |= x >> 8;  // handle 16 bit numbers
	static if (T.sizeof >= 4) x |= x >> 16; // handle 32 bit numbers
	static if (T.sizeof >= 8) x |= x >> 32; // handle 64 bit numbers
	++x;

	return x;
}

struct SizeAndAlign {
	@nogc nothrow:

	enum ALIGN_BITS = 5;
	enum ALIGN_MASK = (1 << ALIGN_BITS) - 1;
	enum SIZE_BITS = 32 - ALIGN_BITS;
	enum SIZE_MASK = (1 << SIZE_BITS) - 1;

	this(u32 size, u32 alignment) {
		import core.bitop : bsf;
		assert(isPowerOfTwo(alignment), "Alignment must be power of two");
		assert((size & SIZE_MASK) == size, "Size must fit into 27 bits");
		u32 alignmentPower = bsf(alignment);
		assert((alignmentPower & ALIGN_MASK) == alignmentPower, "Alignment power must fit into 5 bits");
		payload = (size & SIZE_MASK) | (alignmentPower << SIZE_BITS);
	}

	u32 payload;

	u32 size() const { return payload & SIZE_MASK; }
	u32 alignmentPower() const { return payload >> SIZE_BITS; }
	u32 alignment() const { return 1 << cast(u32)alignmentPower; }

	void toString(scope SinkDelegate sink, FormatSpec spec) const {
		sink.formattedWrite("(size:%s, align:%s)", size(), alignment);
	}
}

bool isPowerOfTwo(T)(T x) pure {
	return (x != 0) && ((x & (~x + 1)) == x);
}

/// alignment is POT
T alignValue(T)(T value, T alignment) {
	enforce(isPowerOfTwo(alignment), "alignment is not power of two (%s)", alignment);
	return cast(T)((value + (alignment-1)) & ~(alignment-1));
}

/// multiple can be NPOT
T roundUp(T)(T value, T multiple) {
	enforce(multiple != 0, "multiple must not be zero");
	return cast(T)(((value + multiple - 1) / multiple) * multiple);
}

T roundDown(T)(T value, T multiple) {
	enforce(multiple != 0, "multiple must not be zero");
	return cast(T)((value / multiple) * multiple);
}

/// alignment is POT
T paddingSize(T)(T address, T alignment) {
	return cast(T)(alignValue(address, alignment) - address);
}

// n - least-significant bits to mask
u64 bitmask(u64 n) {
	if (n >= 64) return u64.max;
	return (1UL << n) - 1;
}

// [16 21f0aaad 15 d35a2d97 15] https://github.com/skeeto/hash-prospector
u32 int32_hash(u32 x) {
    x ^= x >> 16;
    x *= 0x21f0aaad;
    x ^= x >> 15;
    x *= 0xd35a2d97;
    x ^= x >> 15;
    return x;
}

// murmurhash3 64-bit finalizer
u64 hash_u64(u64 x) {
	x ^= x >> 33;
	x *= 0xff51afd7ed558ccd;
	x ^= x >> 33;
	x *= 0xc4ceb9fe1a85ec53;
	x ^= x >> 33;
	return x;
}
