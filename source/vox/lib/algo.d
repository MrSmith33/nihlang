/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.algo;

@nogc nothrow:


void swap(T)(ref T lhs, ref T rhs) pure {
	auto tmp = lhs;
	lhs = rhs;
	rhs = tmp;
}
