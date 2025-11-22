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
// u8 dst/src - u8 register index

enum VmOpcode : u8 {
	// u8 op
	trap,

	// u8 op, s32 offset
	// jumps relative to the address of the next instruction
	jump,

	// u8 op, u8 src, s32 offset
	// if reg[src] is non zero jumps
	// jumps to the address of the next instruction + offset
	branch,

	// u8 op, u8 src, s32 offset
	// if reg[src] is zero jumps
	// jumps to the address of the next instruction + offset
	branch_zero,

	// u8 op, u8 dst, u8 slot_index
	stack_addr,

	// u8 op, SizeAndAlign size_align
	stack_alloc,

	// u8 op, u8 arg0_idx, u8 num_args, u32 func_id
	// Calls a function {func_id}
	// arg0_idx becomes new reg[0] in the callee frame
	// num_args must be equal or greater than number of parameters of {func_id}
	// arg0_idx + num_args <= 256
	call,

	// u8 op, u8 num_args, u32 func_id
	// Calls a function {func_id}
	// reg[0] of the caller becomes reg[0] of the callee
	// num_args must be equal or greater than number of parameters of {func_id}
	// num_args <= 256
	tail_call,

	// u8 op
	ret,

	// u8 op, u8 dst, u8 src
	// reg[dst] = reg[src]
	mov,

	// u8 op, u8 dst, u8 src0, u8 src1
	// reg[dst].i64 = reg[src0].i64 + reg[src1].i64
	// reg[dst].ptr = reg[src0].ptr
	// if (reg[src1].ptr.defined) trap(ERR_PTR_SRC1)
	//
	// Pointer can only occur in the first argument. Pointer is copied to dst
	add_i64,

	// u8 op, u8 dst, u8 src0, u8 src1
	// Valid pointers:
	//   ptr0 - ptr1, where ptr0 == ptr1, dst ptr is null
	//   ptr0 - int, dst ptr is ptr0
	//   int - int, dst ptr is null
	sub_i64,

	// u8 op, u8 dst, u8 src0, u8 src1
	// int * int, dst ptr is null
	mul_i64,

	// u8 op, u8 dst, u8 src0, u8 src1
	// int / int, dst ptr is null
	div_u64,
	div_s64,

	// u8 op, u8 dst, u8 src0, u8 src1
	// int % int, dst ptr is null
	rem_u64,
	rem_s64,

	// u8 op, u8 dst, u8 src
	// Bitwise negation of src
	not_i64,

	// u8 op, u8 dst, u8 src0, u8 src1
	// Bitwise and of src0 and src1
	and_i64,

	// u8 op, u8 dst, u8 src
	// Bitwise or of src0 and src1
	or_i64,

	// u8 op, u8 dst, u8 src
	// Bitwise xor of src0 and src1
	xor_i64,

	// u8 op, u8 dst, u8 src0, u8 src1
	// src0 {shl_NN} (src1 mod NN)
	shl_i8,
	shl_i16,
	shl_i32,
	shl_i64,

	// u8 op, u8 dst, u8 src0, u8 src1
	// src0 {shr_NN} (src1 mod NN), zext
	shr_u8,
	shr_u16,
	shr_u32,
	shr_u64,

	// u8 op, u8 dst, u8 src0, u8 src1
	// src0 {shr_NN} (src1 mod NN), sext
	shr_s8,
	shr_s16,
	shr_s32,
	shr_s64,

	// u8 op, u8 dst, u8 src0, u8 src1
	// src0 {rotl_NN} (src1 mod NN)
	rotl_i8,
	rotl_i16,
	rotl_i32,
	rotl_i64,

	// u8 op, u8 dst, u8 src0, u8 src1
	// src0 {rotr_NN} (src1 mod NN)
	rotr_i8,
	rotr_i16,
	rotr_i32,
	rotr_i64,

	// u8 op, u8 dst, u8 src
	// Count of leading zero bits in src
	// Starting from the most significant bit
	// When src is zero the result is the operand size
	clz_i8,
	clz_i16,
	clz_i32,
	clz_i64,

	// u8 op, u8 dst, u8 src
	// Count of trailing zero bits in src
	// Starting from bit 0
	// When src is zero the result is the operand size
	ctz_i8,
	ctz_i16,
	ctz_i32,
	ctz_i64,

	// u8 op, u8 dst, u8 src
	// Count of non-zero bits in src
	popcnt_i64,

	// u8 op, VmBinCond cmp_op, u8 dst, u8 src0, u8 src1
	// reg[dst].u64 = reg[src0].u64 {cmp_op} reg[src1].u64
	// reg[dst].ptr = null
	cmp,

	// u8 op, u8 dst, s8 src
	// reg[dst].s64 = sext_s8_to_s64(src)
	// reg[dst].ptr = null
	const_s8,

	// u8 op, u8 dst, u8 src
	// u64 offset = reg[src].ptr + reg[src].u64
	// reg[dst].u64 = zext_uXX_to_u64(mem[offset].uXX)
	// reg[dst].ptr = null
	// if (XX == ptr_size && offset.ptr_aligned) reg[dst].ptr = mem[offset].ptr
	load_m8,
	load_m16,
	load_m32,
	load_m64,

	// u8 op, u8 dst, u8 src
	// u64 offset = reg[dst].ptr + reg[dst].u64
	// mem[offset].uXX = reg[src].uXX
	// if (reg[src].ptr.defined && offset.ptr_aligned) reg[dst].ptr = mem[offset].ptr
	store_m8,
	store_m16,
	store_m32,
	store_m64,

	// u8 op, u8 dst, u8 src, u8 len
	memcopy,
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
