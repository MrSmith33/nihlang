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
	// u8 op
	ret,
	trap,

	// u8 op, u8 dst, u8 src
	// reg[u8.dst] = reg[u8.src]
	mov,

	// u8 op, u8 dst, u8 src0, u8 src1
	// reg[dst].u64 = reg[src0].u64 + reg[src1].u64
	// reg[dst].ptr = reg[src0].ptr
	// if (reg[src1].ptr.defined) trap(ERR_PTR_SRC1)
	//
	// Pointer can only occur in first argument
	add_i64,

	// u8 op, u8 dst, s8 src
	// reg[dst] = sext_s8_to_s64(src)
	const_s8,

	// u8 op, u8 dst, s8 src
	// s64 offset = reg[src].ptr + reg[src].s64
	// reg[dst].u64 = zext_uXX_to_u64(mem[offset].uXX)
	// if (XX == ptr_size && offset.ptr_aligned) reg[dst].ptr = mem[offset].ptr
	load_m8,
	load_m16,
	load_m32,
	load_m64,

	// u8 op, u8 dst, s8 src
	// s64 offset = reg[u8.dst].ptr + reg[u8.dst].s64
	// mem[offset].uXX = reg[src].uXX
	// if (reg[src].ptr.defined && offset.ptr_aligned) reg[u8.dst].ptr = mem[offset].ptr
	store_m8,
	store_m16,
	store_m32,
	store_m64,
}
