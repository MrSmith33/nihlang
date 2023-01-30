/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.code_builder;

import vox.lib;
import vox.vm.opcode;

@nogc nothrow:

struct CodeBuilder {
	@nogc nothrow:

	VoxAllocator* allocator;
	Array!u8 code;

	void emit_ret() {
		code.put(*allocator, VmOpcode.ret);
	}

	void emit_trap() {
		code.put(*allocator, VmOpcode.trap);
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

	void emit_mov(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.mov);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_load_m64(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.load_m64);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_store_m64(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.store_m64);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_load_ptr(u8 ptrSize, u8 dst, u8 src) {
		VmOpcode load_op = ptrSize == 4 ? VmOpcode.load_m32 : VmOpcode.load_m64;
		code.put(*allocator, load_op);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_store_ptr(u8 ptrSize, u8 dst, u8 src) {
		VmOpcode store_op = ptrSize == 4 ? VmOpcode.store_m32 : VmOpcode.store_m64;
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
