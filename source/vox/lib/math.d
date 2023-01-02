/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.math;

import vox.lib;

@nogc nothrow:


T min(T)(T a, T b) {
	if (a < b) return a;
	return b;
}

T max(T)(T a, T b) {
	if (a > b) return a;
	return b;
}

bool isPowerOfTwo(T)(T x) {
	return (x != 0) && ((x & (~x + 1)) == x);
}
