/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.tests.tests;

import vox.lib;
import vox.vm;
import vox.vm.tests.infra.test;

@nogc nothrow:

void vmTests(ref VoxAllocator allocator, ref Array!Test tests) {
	return collectTests!(vox.vm.tests.tests)(allocator, tests);
}


@VmTest @(TestAtrib.ptrSize64)
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


@VmTest @(TestAtrib.ptrSize32)
void test_runner_32bit_ptr(ref VmTestContext c) {
	assert(c.vm.ptrSize == 4);
}

@VmTest @(TestAtrib.ptrSize64)
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
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	c.callFail(funcId, VmReg(funcId, 10), VmReg(funcId, 20));
	assert(c.vm.status == VmStatus.ERR_PTR_SRC1);
}

@VmTest
void test_add_i64_3(ref VmTestContext c) {
	// Test add_i64 num + ptr
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 1, 2);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	c.callFail(funcId, VmReg(10), VmReg(funcId, 20));
	assert(c.vm.status == VmStatus.ERR_PTR_SRC1);
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
