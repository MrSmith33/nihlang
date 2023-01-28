/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.math;

public import core.bitop : bsr;
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

i32 signum(T)(const T x) pure {
	return (x > 0) - (x < 0);
}

T divCeil(T)(T a, T b) pure {
	return a / b + (a % b > 0);
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

/// alignment is POT
T paddingSize(T)(T address, T alignment) {
	return cast(T)(alignValue(address, alignment) - address);
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
