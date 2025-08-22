/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.code_builder;

import vox.lib;
import vox.types;
import vox.vm.opcode;
import vox.vm.memory;

@nogc nothrow:

struct CodeBuilder {
	@nogc nothrow:

	VoxAllocator* allocator;
	Array!u8 code;
	Array!SizeAndAlign stack;

	u32 next_addr() {
		return code.length;
	}

	private void U8(u8[] u...) { code.put(*allocator, u); }
	private void U32(u32 u) {
		code.put(*allocator, (u >>  0) & 0xFF);
		code.put(*allocator, (u >>  8) & 0xFF);
		code.put(*allocator, (u >> 16) & 0xFF);
		code.put(*allocator, (u >> 24) & 0xFF);
	}
	private void U32z() {
		code.put(*allocator, 0);
		code.put(*allocator, 0);
		code.put(*allocator, 0);
		code.put(*allocator, 0);
	}

	void add_stack_slot(SizeAndAlign sizeAlign) {
		stack.put(*allocator, sizeAlign);
	}

	void emit_trap() { U8(VmOpcode.trap); }

	void emit_stack_addr(u8 dst, u8 slot_index) {
		U8(VmOpcode.stack_addr, dst, slot_index);
	}

	void emit_stack_alloc(SizeAndAlign sizeAlign) {
		U8(VmOpcode.stack_alloc);
		U32(sizeAlign.payload);
	}

	void emit_call(u8 arg0_idx, u8 num_args, u32 funcIndex) {
		U8(VmOpcode.call, arg0_idx, num_args);
		U32(funcIndex);
	}

	void emit_tail_call(u8 arg0_idx, u8 num_args, u32 funcIndex) {
		U8(VmOpcode.tail_call, arg0_idx, num_args);
		U32(funcIndex);
	}

	void emit_ret() { U8(VmOpcode.ret); }

	u32 emit_jump() {
		U8(VmOpcode.jump);
		U32z();
		return code.length;
	}

	u32 emit_branch(u8 src) {
		U8(VmOpcode.branch, src);
		U32z();
		return code.length;
	}

	u32 emit_branch_zero(u8 src) {
		U8(VmOpcode.branch_zero, src);
		U32z();
		return code.length;
	}

	void patch_rip(u32 patch_addr, u32 target) {
		i32 offset = target - patch_addr;
		code[patch_addr-4+0] = (offset >>  0) & 0xFF;
		code[patch_addr-4+1] = (offset >>  8) & 0xFF;
		code[patch_addr-4+2] = (offset >> 16) & 0xFF;
		code[patch_addr-4+3] = (offset >> 24) & 0xFF;
	}

	void emit_const_s8(u8 dst, i8 src) {
		U8(VmOpcode.const_s8, dst, src);
	}

	void emit_add_i64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.add_i64, dst, src0, src1);
	}

	void emit_sub_i64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.sub_i64, dst, src0, src1);
	}

	void emit_mul_i64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.mul_i64, dst, src0, src1);
	}

	void emit_div_u64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.div_u64, dst, src0, src1);
	}
	void emit_div_s64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.div_s64, dst, src0, src1);
	}
	void emit_rem_u64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.rem_u64, dst, src0, src1);
	}
	void emit_rem_s64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.rem_s64, dst, src0, src1);
	}

	void emit_not_i64(u8 dst, u8 src) {
		U8(VmOpcode.not_i64, dst, src);
	}

	void emit_and_i64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.and_i64, dst, src0, src1);
	}

	void emit_or_i64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.or_i64, dst, src0, src1);
	}

	void emit_xor_i64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.xor_i64, dst, src0, src1);
	}

	void emit_shl_i64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shl_i64, dst, src0, src1);
	}
	void emit_shl_i32(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shl_i32, dst, src0, src1);
	}
	void emit_shl_i16(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shl_i16, dst, src0, src1);
	}
	void emit_shl_i8(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shl_i8, dst, src0, src1);
	}

	void emit_shr_u64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shr_u64, dst, src0, src1);
	}
	void emit_shr_u32(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shr_u32, dst, src0, src1);
	}
	void emit_shr_u16(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shr_u16, dst, src0, src1);
	}
	void emit_shr_u8(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shr_u8, dst, src0, src1);
	}

	void emit_shr_s64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shr_s64, dst, src0, src1);
	}
	void emit_shr_s32(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shr_s32, dst, src0, src1);
	}
	void emit_shr_s16(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shr_s16, dst, src0, src1);
	}
	void emit_shr_s8(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.shr_s8, dst, src0, src1);
	}

	void emit_rotl_i64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.rotl_i64, dst, src0, src1);
	}
	void emit_rotl_i32(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.rotl_i32, dst, src0, src1);
	}
	void emit_rotl_i16(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.rotl_i16, dst, src0, src1);
	}
	void emit_rotl_i8(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.rotl_i8, dst, src0, src1);
	}

	void emit_rotr_i64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.rotr_i64, dst, src0, src1);
	}
	void emit_rotr_i32(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.rotr_i32, dst, src0, src1);
	}
	void emit_rotr_i16(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.rotr_i16, dst, src0, src1);
	}
	void emit_rotr_i8(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.rotr_i8, dst, src0, src1);
	}

	void emit_clz_i64(u8 dst, u8 src) {
		U8(VmOpcode.clz_i64, dst, src);
	}
	void emit_clz_i32(u8 dst, u8 src) {
		U8(VmOpcode.clz_i32, dst, src);
	}
	void emit_clz_i16(u8 dst, u8 src) {
		U8(VmOpcode.clz_i16, dst, src);
	}
	void emit_clz_i8(u8 dst, u8 src) {
		U8(VmOpcode.clz_i8, dst, src);
	}

	void emit_ctz_i64(u8 dst, u8 src) {
		U8(VmOpcode.ctz_i64, dst, src);
	}
	void emit_ctz_i32(u8 dst, u8 src) {
		U8(VmOpcode.ctz_i32, dst, src);
	}
	void emit_ctz_i16(u8 dst, u8 src) {
		U8(VmOpcode.ctz_i16, dst, src);
	}
	void emit_ctz_i8(u8 dst, u8 src) {
		U8(VmOpcode.ctz_i8, dst, src);
	}

	void emit_popcnt_i64(u8 dst, u8 src) {
		U8(VmOpcode.popcnt_i64, dst, src);
	}

	void emit_mov(u8 dst, u8 src) {
		U8(VmOpcode.mov, dst, src);
	}

	void emit_cmp(VmBinCond cond, u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.cmp, cond, dst, src0, src1);
	}

	void emit_load_m8(u8 dst, u8 src) { U8(VmOpcode.load_m8, dst, src); }
	void emit_load_m16(u8 dst, u8 src) { U8(VmOpcode.load_m16, dst, src); }
	void emit_load_m32(u8 dst, u8 src) { U8(VmOpcode.load_m32, dst, src); }
	void emit_load_m64(u8 dst, u8 src) { U8(VmOpcode.load_m64, dst, src); }
	void emit_store_m8(u8 dst, u8 src) { U8(VmOpcode.store_m8, dst, src); }
	void emit_store_m16(u8 dst, u8 src) { U8(VmOpcode.store_m16, dst, src); }
	void emit_store_m32(u8 dst, u8 src) { U8(VmOpcode.store_m32, dst, src); }
	void emit_store_m64(u8 dst, u8 src) { U8(VmOpcode.store_m64, dst, src); }

	void emit_load_ptr(PtrSize ptrSize, u8 dst, u8 src) {
		VmOpcode load_op = ptrSize == PtrSize._32 ? VmOpcode.load_m32 : VmOpcode.load_m64;
		U8(load_op, dst, src);
	}

	void emit_store_ptr(PtrSize ptrSize, u8 dst, u8 src) {
		VmOpcode store_op = ptrSize == PtrSize._32 ? VmOpcode.store_m32 : VmOpcode.store_m64;
		U8(store_op, dst, src);
	}

	void emit_memcopy(u8 dst, u8 src, u8 len) {
		U8(VmOpcode.memcopy, dst, src, len);
	}

	void emit_binop(VmOpcode op, u8 dst, u8 src) {
		U8(op, dst, src);
	}
}
