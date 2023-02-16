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

	u32 next_addr() {
		return code.length;
	}

	void emit_ret() {
		code.put(*allocator, VmOpcode.ret);
	}

	void emit_trap() {
		code.put(*allocator, VmOpcode.trap);
	}

	void emit_push(u8 length) {
		code.put(*allocator, VmOpcode.push);
		code.put(*allocator, length);
	}

	void emit_pop(u8 length) {
		code.put(*allocator, VmOpcode.pop);
		code.put(*allocator, length);
	}

	void emit_call(u32 funcIndex) {
		code.put(*allocator, VmOpcode.call);
		code.put(*allocator, (funcIndex >>  0) & 0xFF);
		code.put(*allocator, (funcIndex >>  8) & 0xFF);
		code.put(*allocator, (funcIndex >> 16) & 0xFF);
		code.put(*allocator, (funcIndex >> 24) & 0xFF);
	}

	u32 emit_jump() {
		code.put(*allocator, VmOpcode.jump);
		code.put(*allocator, 0);
		code.put(*allocator, 0);
		code.put(*allocator, 0);
		code.put(*allocator, 0);
		return code.length;
	}

	u32 emit_branch(u8 src) {
		code.put(*allocator, VmOpcode.branch);
		code.put(*allocator, src);
		code.put(*allocator, 0);
		code.put(*allocator, 0);
		code.put(*allocator, 0);
		code.put(*allocator, 0);
		return code.length;
	}

	void patch_rip(u32 patch_addr, u32 target) {
		i32 offset = target - patch_addr;
		code[patch_addr-4+0] = (offset >>  0) & 0xFF;
		code[patch_addr-4+1] = (offset >>  8) & 0xFF;
		code[patch_addr-4+2] = (offset >> 16) & 0xFF;
		code[patch_addr-4+3] = (offset >> 24) & 0xFF;
	}

	void emit_const_s8(u8 dst, i8 val) {
		code.put(*allocator, VmOpcode.const_s8);
		code.put(*allocator, dst);
		code.put(*allocator, val);
	}

	void emit_add_i64(u8 dst, u8 src0, u8 src1) {
		code.put(*allocator, VmOpcode.add_i64);
		code.put(*allocator, dst);
		code.put(*allocator, src0);
		code.put(*allocator, src1);
	}

	void emit_sub_i64(u8 dst, u8 src0, u8 src1) {
		code.put(*allocator, VmOpcode.sub_i64);
		code.put(*allocator, dst);
		code.put(*allocator, src0);
		code.put(*allocator, src1);
	}

	void emit_mov(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.mov);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_cmp(VmBinCond cond, u8 dst, u8 src0, u8 src1) {
		code.put(*allocator, VmOpcode.cmp);
		code.put(*allocator, cond);
		code.put(*allocator, dst);
		code.put(*allocator, src0);
		code.put(*allocator, src1);
	}

	void emit_load_m8(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.load_m8);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_load_m16(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.load_m16);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_load_m32(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.load_m32);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_load_m64(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.load_m64);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_store_m8(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.store_m8);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_store_m16(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.store_m16);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_store_m32(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.store_m32);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_store_m64(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.store_m64);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_load_ptr(PtrSize ptrSize, u8 dst, u8 src) {
		VmOpcode load_op = ptrSize == PtrSize._32 ? VmOpcode.load_m32 : VmOpcode.load_m64;
		code.put(*allocator, load_op);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_store_ptr(PtrSize ptrSize, u8 dst, u8 src) {
		VmOpcode store_op = ptrSize == PtrSize._32 ? VmOpcode.store_m32 : VmOpcode.store_m64;
		code.put(*allocator, store_op);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_binop(VmOpcode op, u8 dst, u8 src) {
		code.put(*allocator, op);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}
}
