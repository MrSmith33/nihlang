/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.opcode;

import vox.lib;

@nogc nothrow:

// m - anything
// v - simd vectors
// f - float
// i - signed or unsigned int
// u - unsigned int
// s - signed int
// p - pointer

enum VmOpcode : u8 {
	ret,

	mov,

	add_i64,

	// sign-extended to i64
	const_s8,

	// zero-extended to u64
	load_m8,
	load_m16,
	load_m32,
	load_m64,

	store_m8,
	store_m16,
	store_m32,
	store_m64,
}
