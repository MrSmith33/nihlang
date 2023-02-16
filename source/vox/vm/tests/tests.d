/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.tests.tests;

import vox.lib;
import vox.vm;
import vox.vm.tests.infra;

@nogc nothrow:

void vmTests(ref VoxAllocator allocator, ref TestSuite suite) {
	return collectTests!(vox.vm.tests.tests)(allocator, suite);
}

// Test ideas:
// - What if the same register/memory is used multiple times in an instruction
// - Check that state is not changed on trap
//   - Memory init bits are not changed on trapped store


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
	assert(c.vm.ptrSize == PtrSize._32);
}

@VmTest @TestPtrSize64
void test_runner_64bit_ptr(ref VmTestContext c) {
	assert(c.vm.ptrSize == PtrSize._64);
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
void test_jump_0(ref VmTestContext c) {
	// Test jump
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_const_s8(0,  0);
	u32 patch_addr = b.emit_jump();
	b.emit_const_s8(0, -1); // shouldn't execute
	u32 ret_addr = b.next_addr;
	b.emit_ret();
	b.patch_rip(patch_addr, ret_addr);
	AllocId funcId = c.vm.addFunction(b.code, 1, 0, 0);
	VmReg[] res = c.call(funcId);
	assert(res[0] == VmReg(0));
}


@VmTest
void test_branch_0(ref VmTestContext c) {
	// Test jump
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	u32 patch_addr = b.emit_branch(1);
	b.emit_const_s8(0, 0);
	b.emit_ret();
	u32 true_addr = b.next_addr;
	b.emit_const_s8(0, 1);
	b.emit_ret();
	b.patch_rip(patch_addr, true_addr);
	AllocId funcId = c.vm.addFunction(b.code, 1, 1, 0);
	VmReg[] res;

	res = c.call(funcId, VmReg(0));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(10));
	assert(res[0] == VmReg(1));
	c.clearStack;

	// branch on pointer
	res = c.call(funcId, VmReg(funcId, 0));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(funcId, 10));
	assert(res[0] == VmReg(1));
	c.clearStack;
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
void test_cmp_0(ref VmTestContext c) {
	// Test cmp OOB condition
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(cast(VmBinCond)(VmBinCond.max+1), 0, 1, 2);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 0);
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_COND_OOB);
}

@VmTest
void test_cmp_1(ref VmTestContext c) {
	// Test cmp OOB dst register
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.min, 0, 1, 2);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 0); // 0 locals
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 0); // r0
}

@VmTest
void test_cmp_2(ref VmTestContext c) {
	// Test cmp OOB src0 register
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.min, 0, 1, 2);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 1); // 1 local
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 1); // r1
}

@VmTest
void test_cmp_3(ref VmTestContext c) {
	// Test cmp OOB src1 register
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.min, 0, 1, 2);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 0, 2); // 2 locals
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_REGISTER_OOB);
	assert(c.vm.errData == 2); // r2
}

@VmTest
void test_cmp_4(ref VmTestContext c) {
	// Test cmp.m64.eq
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.m64_eq, 0, 1, 2);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId memId2 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	VmReg[] res;

	// ptr is null
	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(0));
	c.clearStack;

	// ptr is not null
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 10));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 20));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId2, 10));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId2, 20));
	assert(res[0] == VmReg(0));
	c.clearStack;
}

@VmTest
void test_cmp_5(ref VmTestContext c) {
	// Test cmp.m64.ne
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.m64_ne, 0, 1, 2);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId memId2 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	VmReg[] res;

	// ptr is null
	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(1));
	c.clearStack;

	// ptr is not null
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 10));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 20));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId2, 10));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId2, 20));
	assert(res[0] == VmReg(1));
	c.clearStack;
}

@VmTest
void test_cmp_6(ref VmTestContext c) {
	// Test cmp.u64.gt
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.u64_gt, 0, 1, 2);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	VmReg[] res;

	// ptr is null
	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(20), VmReg(10));
	assert(res[0] == VmReg(1));
	c.clearStack;

	// ptr is not null
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 10));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 20));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(memId1, 20), VmReg(memId1, 10));
	assert(res[0] == VmReg(1));
	c.clearStack;
}

@VmTest
void test_cmp_7(ref VmTestContext c) {
	// Test cmp.u64.ge
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.u64_ge, 0, 1, 2);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	VmReg[] res;

	// ptr is null
	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(20), VmReg(10));
	assert(res[0] == VmReg(1));
	c.clearStack;

	// ptr is not null
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 10));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 20));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(memId1, 20), VmReg(memId1, 10));
	assert(res[0] == VmReg(1));
	c.clearStack;
}

@VmTest
@VmTestParam(TestParamId.user, [VmBinCond.u64_gt, VmBinCond.u64_ge])
void test_cmp_8(ref VmTestContext c) {
	// Test cmp.u64.gt/ge different pointers
	VmBinCond cond = cast(VmBinCond)c.test.getParam(TestParamId.user);
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(cond, 0, 1, 2);
	b.emit_trap();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId memId2 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	c.callFail(funcId, VmReg(memId1, 10), VmReg(memId2, 10));
	assert(c.vm.status == VmStatus.ERR_CMP_DIFFERENT_PTR);
}

@VmTest
@VmTestParam(TestParamId.user, [
	VmBinCond.s64_gt, VmBinCond.s64_ge, VmBinCond.f32_gt, VmBinCond.f32_ge, VmBinCond.f64_gt, VmBinCond.f64_ge,])
void test_cmp_9(ref VmTestContext c) {
	// Test cmp condition that requires pointers to be null
	VmBinCond cond = cast(VmBinCond)c.test.getParam(TestParamId.user);
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(cond, 0, 1, 2);
	b.emit_trap();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	c.callFail(funcId, VmReg(memId1, 10), VmReg(memId1, 10));
	assert(c.vm.status == VmStatus.ERR_CMP_REQUIRES_NO_PTR);
	c.clearStack;
	c.callFail(funcId, VmReg(memId1, 10), VmReg(10));
	assert(c.vm.status == VmStatus.ERR_CMP_REQUIRES_NO_PTR);
	c.clearStack;
	c.callFail(funcId, VmReg(10), VmReg(memId1, 10));
	assert(c.vm.status == VmStatus.ERR_CMP_REQUIRES_NO_PTR);
}

@VmTest
void test_cmp_10(ref VmTestContext c) {
	// Test cmp.s64.gt
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.s64_gt, 0, 1, 2);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	VmReg[] res;

	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(20), VmReg(10));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(-20), VmReg(-10));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(-20), VmReg(-20));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(-10), VmReg(-20));
	assert(res[0] == VmReg(1));
	c.clearStack;
}

@VmTest
void test_cmp_11(ref VmTestContext c) {
	// Test cmp.s64.ge
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.s64_ge, 0, 1, 2);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);
	VmReg[] res;

	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(20), VmReg(10));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(-20), VmReg(-10));
	assert(res[0] == VmReg(0));
	c.clearStack;
	res = c.call(funcId, VmReg(-20), VmReg(-20));
	assert(res[0] == VmReg(1));
	c.clearStack;
	res = c.call(funcId, VmReg(-10), VmReg(-20));
	assert(res[0] == VmReg(1));
	c.clearStack;
}

@VmTest
void test_cmp_12(ref VmTestContext c) {
	// Test cmp.f32
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.f32_gt, 0, 4, 5);
	b.emit_cmp(VmBinCond.f32_ge, 1, 4, 5);
	b.emit_cmp(VmBinCond.f32_gt, 2, 4, 5);
	b.emit_cmp(VmBinCond.f32_ge, 3, 4, 5);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(b.code, 4, 2, 0);
	VmReg[] res = c.call(funcId, VmReg(cast(f32)100.0), VmReg(cast(f32)50.0));
	assert(res[0] == VmReg(1)); // 100 >  50
	assert(res[1] == VmReg(1)); // 100 >= 50
	assert(res[2] == VmReg(1)); // 100 >  100
	assert(res[3] == VmReg(1)); // 100 >= 100
}

@VmTest
void test_cmp_13(ref VmTestContext c) {
	// Test cmp.f64
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.f64_gt, 0, 4, 5);
	b.emit_cmp(VmBinCond.f64_ge, 1, 4, 5);
	b.emit_cmp(VmBinCond.f64_gt, 2, 4, 5);
	b.emit_cmp(VmBinCond.f64_ge, 3, 4, 5);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(b.code, 4, 2, 0);
	VmReg[] res = c.call(funcId, VmReg(cast(f64)100.0), VmReg(cast(f64)50.0));
	assert(res[0] == VmReg(1)); // 100 >  50
	assert(res[1] == VmReg(1)); // 100 >= 50
	assert(res[2] == VmReg(1)); // 100 >  100
	assert(res[3] == VmReg(1)); // 100 >= 100
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
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	c.callFail(funcId, VmReg(0), VmReg(memId, 8));
	assert(c.vm.status == VmStatus.ERR_LOAD_OOB);
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.load_m8, VmOpcode.load_m16, VmOpcode.load_m32, VmOpcode.load_m64])
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_load_mXX_6(ref VmTestContext c) {
	// Test load_mXX src memory uninitialized
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	c.callFail(funcId, VmReg(0), VmReg(memId, 0));
	assert(c.vm.status == VmStatus.ERR_LOAD_UNINIT);
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.load_m8, VmOpcode.load_m16, VmOpcode.load_m32, VmOpcode.load_m64])
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_load_mXX_7(ref VmTestContext c) {
	// Test load_mXX raw bytes with offset from 0 to 8
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	u64 sizeMask = bitmask(1 << (op - VmOpcode.load_m8 + 3));
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(16, 1));
	u64 value0 = 0x_88_77_66_55_44_33_22_11_UL;
	u64 value1 = 0x_F1_FF_EE_DD_CC_BB_AA_99_UL;
	c.vm.memWrite!u64(memId, 0, value0); // fill memory with data
	c.vm.memWrite!u64(memId, 8, value1); // fill memory with data
	c.vm.markInitialized(memId, 0, 16);  // make memory initialized
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 1, 0);

	foreach(offset; 0..9) {
		u64 shiftSize  = offset * 8;
		u64 shiftSize2 = 64 - shiftSize;
		u64 val0 = shiftSize == 64 ? 0 : value0 >> shiftSize;
		u64 val1 = shiftSize2 == 64 ? 0 : value1 << shiftSize2;
		u64 val  = (val1 | val0) & sizeMask;
		//writefln("read %02X", res[0].as_u64);
		//writefln("  val0 %016X", val0);
		//writefln("  val1 %016X", val1);
		//writefln("  val  %016X", val1 | val0);
		//writefln("  mask %02X", val);

		VmReg[] res = c.call(funcId, VmReg(memId, offset));
		assert(res[0] == VmReg(val));
		c.clearStack;
	}
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.load_m8, VmOpcode.load_m16, VmOpcode.load_m32, VmOpcode.load_m64])
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_load_mXX_8(ref VmTestContext c) {
	// Test load_mXX on pointer bytes with offset from 0 to 8
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	u32 size = 1 << (op - VmOpcode.load_m8);
	u64 sizeMask = bitmask(1 << (op - VmOpcode.load_m8 + 3));

	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(16, 1));
	u64 value0 = 0x_88_77_66_55_44_33_22_11_UL;
	u64 value1 = 0x_F1_FF_EE_DD_CC_BB_AA_99_UL;
	c.vm.memWrite!u64(memId, 0, value0); // fill memory with data
	c.vm.memWrite!u64(memId, 8, value1); // fill memory with data
	c.vm.markInitialized(memId, 0, 16);  // make memory initialized
	c.memWritePtr(memId, 0, memId);

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 1, 0);

	foreach(offset; 0..9) {
		u64 shiftSize  = offset * 8;
		u64 shiftSize2 = 64 - shiftSize;
		u64 val0 = shiftSize == 64 ? 0 : value0 >> shiftSize;
		u64 val1 = shiftSize2 == 64 ? 0 : value1 << shiftSize2;
		u64 val  = (val1 | val0) & sizeMask;

		VmReg[] res = c.call(funcId, VmReg(memId, offset));
		if (size == c.vm.ptrSize.inBytes && offset == 0) {
			// writefln("op %s size %s mem %s offset %s", op, size, memKind, offset);
			assert(res[0] == VmReg(memId, val));
		} else {
			assert(res[0] == VmReg(val));
		}
		c.clearStack;
	}
}


@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.store_m8, VmOpcode.store_m16, VmOpcode.store_m32, VmOpcode.store_m64])
void test_store_mXX_0(ref VmTestContext c) {
	// Test store_mXX OOB dst register
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
@VmTestParam(TestParamId.instr, [VmOpcode.store_m8, VmOpcode.store_m16, VmOpcode.store_m32, VmOpcode.store_m64])
void test_store_mXX_1(ref VmTestContext c) {
	// Test store_mXX OOB src register
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
@VmTestParam(TestParamId.instr, [VmOpcode.store_m8, VmOpcode.store_m16, VmOpcode.store_m32, VmOpcode.store_m64])
void test_store_mXX_2(ref VmTestContext c) {
	// Test store_mXX dst pointer undefined
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	c.callFail(funcId, VmReg(0), VmReg(0));
	assert(c.vm.status == VmStatus.ERR_STORE_NOT_PTR);
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.store_m8, VmOpcode.store_m16, VmOpcode.store_m32, VmOpcode.store_m64])
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem, MemoryKind.func_id])
void test_store_mXX_3(ref VmTestContext c) {
	// Test store_mXX dst memory is not writable
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	AllocId memId;
	if (memKind != MemoryKind.func_id) {
		memId = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));
	}
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	if (memKind == MemoryKind.func_id) memId = funcId;
	c.vm.readWriteMask = 0; // everything is non-writable
	c.callFail(funcId, VmReg(memId), VmReg(0));
	assert(c.vm.status == VmStatus.ERR_STORE_NO_WRITE_PERMISSION);
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.store_m8, VmOpcode.store_m16, VmOpcode.store_m32, VmOpcode.store_m64])
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_store_mXX_4(ref VmTestContext c) {
	// Test store_mXX dst memory offset is negative
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	c.callFail(funcId, VmReg(memId, -1), VmReg(0));
	assert(c.vm.status == VmStatus.ERR_STORE_OOB);
}

@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.store_m8, VmOpcode.store_m16, VmOpcode.store_m32, VmOpcode.store_m64])
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_store_mXX_5(ref VmTestContext c) {
	// Test store_mXX dst memory offset is too big
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);
	c.callFail(funcId, VmReg(memId, 8), VmReg(0));
	assert(c.vm.status == VmStatus.ERR_STORE_OOB);
}

@VmTest
@VmTestParam(TestParamId.user, [0, 1, 2, 3])
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_store_mXX_6(ref VmTestContext c) {
	// Test store_mXX raw bytes with offset from 0 to 8
	// Check that init bits are set
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	u32 param = c.test.getParam(TestParamId.user);
	u32 size = 1 << param;
	u64 sizeMask = bitmask(1 << param+3);
	u64 value = 0x_88_77_66_55_44_33_22_11_UL;
	VmOpcode store_op = cast(VmOpcode)(VmOpcode.store_m8 + param);
	VmOpcode load_op = cast(VmOpcode)(VmOpcode.load_m8 + param);
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(16, 1));

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(store_op, 1, 2);
	b.emit_binop(load_op, 0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);

	foreach(offset; 0..9) {
		VmReg[] res = c.call(funcId, VmReg(memId, offset), VmReg(value));
		// should not init unrelated bytes
		assert(c.countAllocInitBits(memId) == size);
		assert(res[0] == VmReg(value & sizeMask));

		// mark whole allocation as uninitialized
		c.setAllocInitBits(memId, false);
		c.clearStack;
	}
}

@VmTest
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_store_mXX_7(ref VmTestContext c) {
	// Test store_mXX of pointers to unaligned address
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(16, 1));

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_store_ptr(c.vm.ptrSize, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(b.code, 0, 2, 0);

	foreach(offset; 1..c.vm.ptrSize.inBytes) {
		c.callFail(funcId, VmReg(memId, offset), VmReg(memId));
		assert(c.vm.status == VmStatus.ERR_STORE_PTR_UNALIGNED);

		// memory was not touched by unsuccessful store
		assert(c.countAllocInitBits(memId) == 0);
	}
}

@VmTest
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_store_mXX_8(ref VmTestContext c) {
	// Test store_mXX of pointers to aligned address
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_store_ptr(c.vm.ptrSize, 1, 2); // store memId
	b.emit_load_ptr(c.vm.ptrSize, 0, 1); //   load memId
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 2, 0);

	VmReg[] res = c.call(funcId, VmReg(memId), VmReg(memId));
	assert(res[0] == VmReg(memId));
}

@VmTest
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_store_mXX_9(ref VmTestContext c) {
	// Test store_mXX of pointers to aligned address that overwrites an existing pointer
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	AllocId memId1 = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));
	AllocId memId2 = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_store_ptr(c.vm.ptrSize, 1, 2); // store memId1
	b.emit_store_ptr(c.vm.ptrSize, 1, 3); // store memId2 (overwrites memId1)
	b.emit_load_ptr(c.vm.ptrSize, 0, 1);  //  load memId2
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 3, 0);

	VmReg[] res = c.call(funcId, VmReg(memId1), VmReg(memId1), VmReg(memId2));
	assert(res[0] == VmReg(memId2));
}

@VmTest
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_store_mXX_10(ref VmTestContext c) {
	// Test store_mXX of non-pointer to aligned address that removes an existing pointer
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_store_ptr(c.vm.ptrSize, 1, 2); // store memId
	b.emit_store_ptr(c.vm.ptrSize, 1, 3); // store 0
	b.emit_load_ptr(c.vm.ptrSize, 0, 1);  //  load 0
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(b.code, 1, 3, 0);

	VmReg[] res = c.call(funcId, VmReg(memId), VmReg(memId), VmReg(0));
	assert(res[0] == VmReg(0));
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
	AllocId staticId = c.staticAlloc(SizeAndAlign(c.vm.ptrSize.inBytes, 1));
	AllocId heapId   = c.heapAlloc(SizeAndAlign(c.vm.ptrSize.inBytes, 1));
	AllocId stackId  = c.stackAlloc(SizeAndAlign(c.vm.ptrSize.inBytes, 1));

	VmReg[] res = c.call(funcId, VmReg(funcId), VmReg(staticId), VmReg(heapId), VmReg(stackId));
	assert(res[0] == VmReg(heapId));
}
