/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.code_builder;

import vox.lib;
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

	void emit_ret() { U8(VmOpcode.ret); }
	void emit_trap() { U8(VmOpcode.trap); }

	void emit_call(u8 arg0_idx, u8 num_args, u32 funcIndex) {
		U8(VmOpcode.call, arg0_idx, num_args);
		U32(funcIndex);
	}

	void emit_tail_call(u8 num_args, u32 funcIndex) {
		U8(VmOpcode.tail_call, num_args);
		U32(funcIndex);
	}

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

	u32 emit_branch_ge(u8 src0, u8 src1) {
		U8(VmOpcode.branch_ge, src0, src1);
		U32z();
		return code.length;
	}

	u32 emit_branch_le_imm8(u8 src0, u8 src1) {
		U8(VmOpcode.branch_le_imm8, src0, src1);
		U32z();
		return code.length;
	}

	u32 emit_branch_gt_imm8(u8 src0, u8 src1) {
		U8(VmOpcode.branch_gt_imm8, src0, src1);
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

	void emit_add_i64_imm8(u8 dst, u8 src0, i8 src1) {
		U8(VmOpcode.add_i64_imm8, dst, src0, src1);
	}

	void emit_sub_i64(u8 dst, u8 src0, u8 src1) {
		U8(VmOpcode.sub_i64, dst, src0, src1);
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

	void emit_binop(VmOpcode op, u8 dst, u8 src) {
		U8(op, dst, src);
	}
}
