/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.tests.tests;

import vox.lib;
import vox.vm;
import vox.vm.tests.infra;

@nogc nothrow:

void vmTests(ref VoxAllocator allocator, ref Array!Test tests) {
	return collectTests!(vox.vm.tests.tests)(allocator, tests);
}


@VmTest @TestPtrSize64
void test_warmup(ref VmTestContext c) {
	// Big code to warmup the memory and caches
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_mov(0, 1);
	b.emit_mov(0, 1);
	b.emit_mov(0, 1);
	b.emit_mov(0, 1);
	b.emit_mov(0, 1);
	b.emit_mov(0, 1);
	b.emit_mov(0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 2);
	c.call(funcId);
}


@VmTest @TestPtrSize32
void test_runner_32bit_ptr(ref VmTestContext c) {
	assert(c.vm.ptrSize == 4);
}

@VmTest @TestPtrSize64
void test_runner_64bit_ptr(ref VmTestContext c) {
	assert(c.vm.ptrSize == 8);
}


@VmTest
void test_ret_0(ref VmTestContext c) {
	// Test return with 0 results 0 parameters and 0 locals
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 0);
	VmReg[] res = c.call(funcId);
	assert(res.length == 0);
}

@VmTest
void test_ret_1(ref VmTestContext c) {
	// Test return with 0 results 0 parameters and 1 local
	// Check that local is removed from the stack by the ret handler
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 1);
	VmReg[] res = c.call(funcId);
	assert(res.length == 0);
	assert(c.vm.registers.length == 0);
}

@VmTest
void test_ret_2(ref VmTestContext c) {
	// Test return with 0 results 2 parameters and 0 locals
	// Check that parameters are removed from the stack by the ret handler
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	VmReg[] res = c.call(funcId, VmReg(42), VmReg(33));
	assert(res.length == 0);
	assert(c.vm.registers.length == 0);
}

@VmTest
void test_ret_3(ref VmTestContext c) {
	// Test return with 0 results 2 parameters and 2 locals
	// Check that locals and parameters are removed from the stack by the ret handler
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 2);
	VmReg[] res = c.call(funcId, VmReg(42), VmReg(33));
	assert(res.length == 0);
	assert(c.vm.registers.length == 0);
}


@VmTest
void test_trap_0(ref VmTestContext c) {
	// Test trap
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 0);
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_TRAP);
}


@VmTest
void test_mov_0(ref VmTestContext c) {
	// Test mov of non-pointer from parameter to result
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 1, 0);
	VmReg[] res = c.call(funcId, VmReg(42));
	assert(res[0] == VmReg(42));
}

@VmTest
void test_mov_1(ref VmTestContext c) {
	// Test mov of pointer from parameter to result
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 1, 0);
	VmReg[] res = c.call(funcId, VmReg(funcId));
	assert(res[0] == VmReg(funcId));
}

@VmTest
void test_mov_2(ref VmTestContext c) {
	// Test mov of pointer with offset from parameter to result
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 1, 0);
	VmReg[] res = c.call(funcId, VmReg(funcId, 42));
	assert(res[0] == VmReg(funcId, 42));
}

@VmTest
void test_mov_3(ref VmTestContext c) {
	// Test mov of non-pointer from uninitialized local to result
	// TODO: This may be either catched during validation, or we could have a bit per register and check it
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 0, 1);
	VmReg[] res = c.call(funcId);
}

@VmTest
void test_mov_4(ref VmTestContext c) {
	// Test mov OOB dst register
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 0); // 0 locals
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 0); // r0
}

@VmTest
void test_mov_5(ref VmTestContext c) {
	// Test mov OOB src register
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 1); // 1 local
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 1); // r1
}


@VmTest
void test_add_i64_0(ref VmTestContext c) {
	// Test add_i64 number addition
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 1, 2);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	VmReg[] res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(30));
}

@VmTest
void test_add_i64_1(ref VmTestContext c) {
	// Test add_i64 ptr + number
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 1, 2);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	VmReg[] res = c.call(funcId, VmReg(funcId, 10), VmReg(20));
	assert(res[0] == VmReg(funcId, 30));
}

@VmTest
void test_add_i64_2(ref VmTestContext c) {
	// Test add_i64 ptr + ptr
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 1, 2);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	c.callFail(funcId, VmReg(funcId, 10), VmReg(funcId, 20));
	assert(c.vm.status == VmStatus.ERR_PTR_SRC1);
}

@VmTest
void test_add_i64_3(ref VmTestContext c) {
	// Test add_i64 num + ptr
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 1, 2);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	c.callFail(funcId, VmReg(10), VmReg(funcId, 20));
	assert(c.vm.status == VmStatus.ERR_PTR_SRC1);
}

@VmTest
void test_add_i64_4(ref VmTestContext c) {
	// Test add_i64 OOB dst register
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 1, 2);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 0); // 0 locals
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 0); // r0
}

@VmTest
void test_add_i64_5(ref VmTestContext c) {
	// Test add_i64 OOB src0 register
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 1, 2);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 1); // 1 local
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 1); // r1
}

@VmTest
void test_add_i64_6(ref VmTestContext c) {
	// Test add_i64 OOB src1 register
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 1, 2);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 2); // 2 locals
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 2); // r2
}


@VmTest
void test_const_s8_0(ref VmTestContext c) {
	// Test const_s8
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_const_s8(0, -1);
	b.emit_const_s8(1,  1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 2, 0, 0);
	VmReg[] res = c.call(funcId);
	assert(res[0] == VmReg(-1));
	assert(res[1] == VmReg( 1));
}

@VmTest
void test_const_s8_4(ref VmTestContext c) {
	// Test const_s8 OOB dst register
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_const_s8(0, 0);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 0); // 0 locals
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 0); // r0
}


@VmTest
void test_load_m8_0(ref VmTestContext c) {
	// Test load_m8
	AllocId staticId = c.staticAlloc(SizeAndAlign(1, 1));
	c.vm.memWrite!u8(staticId, 0, 42);

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_load_m8(0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 1, 0);
	VmReg[] res = c.call(funcId, VmReg(staticId));
	assert(res[0] == VmReg(42));
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.load_m8, VmOpcode.load_m16, VmOpcode.load_m32, VmOpcode.load_m64])
void test_load_mXX_0(ref VmTestContext c) {
	// Test load_mXX OOB dst register
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 0);
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 0); // r0
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.load_m8, VmOpcode.load_m16, VmOpcode.load_m32, VmOpcode.load_m64])
void test_load_mXX_1(ref VmTestContext c) {
	// Test load_mXX OOB src register
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 1);
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 1); // r1
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.load_m8, VmOpcode.load_m16, VmOpcode.load_m32, VmOpcode.load_m64])
void test_load_mXX_2(ref VmTestContext c) {
	// Test load_mXX src pointer undefined
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	c.callFail(funcId, VmReg(0), VmReg(0));
	assert(c.vm.status == VmStatus.ERR_LOAD_NOT_PTR);
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.load_m8, VmOpcode.load_m16, VmOpcode.load_m32, VmOpcode.load_m64])
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem, MemoryKind.func_id])
void test_load_mXX_3(ref VmTestContext c) {
	// Test load_mXX src memory is not readable
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	AllocId memId;
	if (memKind != MemoryKind.func_id) {
		memId = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));
		c.vm.memWrite!u64(memId, 0, 0); // make memory initialized
	}

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	if (memKind == MemoryKind.func_id) memId = funcId;
	c.vm.readWriteMask = 0; // everything is non-readable
	c.callFail(funcId, VmReg(0), VmReg(memId));
	assert(c.vm.status == VmStatus.ERR_LOAD_NO_READ_PERMISSION);
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.load_m8, VmOpcode.load_m16, VmOpcode.load_m32, VmOpcode.load_m64])
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_load_mXX_4(ref VmTestContext c) {
	// Test load_mXX src memory offset is negative
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));
	c.vm.memWrite!u64(memId, 0, 0); // make memory initialized
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	c.callFail(funcId, VmReg(0), VmReg(memId, -1));
	assert(c.vm.status == VmStatus.ERR_LOAD_OOB);
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.load_m8, VmOpcode.load_m16, VmOpcode.load_m32, VmOpcode.load_m64])
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_load_mXX_5(ref VmTestContext c) {
	// Test load_mXX src memory offset is too big
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));
	c.vm.memWrite!u64(memId, 0, 0); // make memory initialized
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	c.callFail(funcId, VmReg(0), VmReg(memId, 8));
	assert(c.vm.status == VmStatus.ERR_LOAD_OOB);
}


@VmTest
void test100(ref VmTestContext c) {
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_store_ptr(c.vm.ptrSize, 2, 1);
	b.emit_store_ptr(c.vm.ptrSize, 3, 2);
	b.emit_store_ptr(c.vm.ptrSize, 4, 3);
	b.emit_load_ptr(c.vm.ptrSize, 0, 4);
	b.emit_ret();

	AllocId funcId   = c.vm.addFunction(b.code, 1, 4, 0);
	AllocId staticId = c.staticAlloc(SizeAndAlign(c.vm.ptrSize, 1));
	AllocId heapId   = c.heapAlloc(SizeAndAlign(c.vm.ptrSize, 1));
	AllocId stackId  = c.stackAlloc(SizeAndAlign(c.vm.ptrSize, 1));

	VmReg[] res = c.call(funcId, VmReg(funcId), VmReg(staticId), VmReg(heapId), VmReg(stackId));
	assert(res[0] == VmReg(heapId));
}
