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

	// u8 op, s32 offset
	// jumps relative to the address of the next instruction
	jump,

	// u8 op, u8 src, s32 offset
	// if reg[src] is non zero jumps
	// jumps relative to the address of the next instruction
	branch,

	// u8 op, u8 length
	// pushed {length} registers on the stack
	// used to allocate results and parameters for a function call
	push,

	// u8 op, u8 length
	// pops {length} registers from the stack
	// used to deallocate results after a function call
	// Cannot only pop registers that were pushed
	// Function registers (results, parameters, locals) can not be popped
	pop,

	// u8 op, u32 func_id
	// Calls a function passing all pushed registers as results/parameters
	call,

	// u8 op, u8 dst, u8 src
	// reg[dst] = reg[src]
	mov,

	// u8 op, u8 dst, u8 src0, u8 src1
	// reg[dst].u64 = reg[src0].u64 + reg[src1].u64
	// reg[dst].ptr = reg[src0].ptr
	// if (reg[src1].ptr.defined) trap(ERR_PTR_SRC1)
	//
	// Pointer can only occur in first argument
	add_i64,

	// u8 op, u8 dst, u8 src0, u8 src1
	sub_i64,

	// u8 op, VmBinCond cmp_op, u8 dst, u8 src0, u8 src1
	// reg[dst].u64 = reg[src0].u64 {cmp_op} reg[src1].u64
	// reg[dst].ptr = null
	cmp,

	// u8 op, u8 dst, s8 src
	// reg[dst].s64 = sext_s8_to_s64(src)
	// reg[dst].ptr = null
	const_s8,

	// u8 op, u8 dst, s8 src
	// s64 offset = reg[src].ptr + reg[src].s64
	// reg[dst].u64 = zext_uXX_to_u64(mem[offset].uXX)
	// reg[dst].ptr = null
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

enum VmBinCond : ubyte {
	m64_eq,
	m64_ne,

	u64_gt,
	u64_ge,

	s64_gt,
	s64_ge,

	f32_gt,
	f32_ge,

	f64_gt,
	f64_ge,
}

immutable string[10] vmBinCondString = [
	"m64.eq", "m64.ne", "u64.gt", "u64.ge", "s64.gt", "s64.ge",
	"f32.gt", "f32.ge", "f64.gt", "f64.ge",
];
