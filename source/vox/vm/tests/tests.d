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
	AllocId funcId = c.vm.addFunction(0.NumResults, 0.NumRegParams, 0.NumStackParams, b);
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
	// Test return with 0 results 0 parameters
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(0.NumResults, 0.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId);
	assert(res.length == 0);
	assert(c.vm.frameFirstReg == 0);
	assert(c.vm.registers.length == 256);
}

@VmTest
void test_ret_1(ref VmTestContext c) {
	// Test return with 0 results 2 parameters
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId, VmReg(42), VmReg(33));
	assert(res.length == 0);
	assert(c.vm.frameFirstReg == 0);
	assert(c.vm.registers.length == 256);
}

@VmTest
void test_ret_2(ref VmTestContext c) {
	// Test return with 2 results 2 parameters
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(2.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId, VmReg(42), VmReg(33));
	assert(res.length == 2);
	assert(c.vm.frameFirstReg == 0);
	assert(c.vm.registers.length == 256);
}


@VmTest
void test_trap_0(ref VmTestContext c) {
	// Test trap
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(0.NumResults, 0.NumRegParams, 0.NumStackParams, b);
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_TRAP);
}


@VmTest
void test_budget_0(ref VmTestContext c) {
	// Test budget
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(0.NumResults, 0.NumRegParams, 0.NumStackParams, b);

	// check that budget of 0 is not enough to run single instruction
	c.vm.budget = 0;
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_BUDGET);

	// check that budget of 1 is enough to run single instruction
	c.vm.budget = 1;
	c.call(funcId);

	// check that budget gets reset per test
	c.vm.budget = 0;
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
	AllocId funcId = c.vm.addFunction(1.NumResults, 0.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId);
	assert(res[0] == VmReg(0));
}


@VmTest
void test_branch_0(ref VmTestContext c) {
	// Test branch
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	u32 patch_addr = b.emit_branch(0);
	b.emit_const_s8(0, 0);
	b.emit_ret();
	u32 true_addr = b.next_addr;
	b.emit_const_s8(0, 1);
	b.emit_ret();
	b.patch_rip(patch_addr, true_addr);
	AllocId funcId = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, b);
	VmReg[] res;

	res = c.call(funcId, VmReg(0));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(10));
	assert(res[0] == VmReg(1));

	// branch on pointer
	res = c.call(funcId, VmReg(funcId, 0));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(funcId, 10));
	assert(res[0] == VmReg(1));
}


@VmTest
void test_branch_zero_0(ref VmTestContext c) {
	// Test branch zero
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	u32 patch_addr = b.emit_branch_zero(0);
	b.emit_const_s8(0, 1);
	b.emit_ret();
	u32 true_addr = b.next_addr;
	b.emit_const_s8(0, 0);
	b.emit_ret();
	b.patch_rip(patch_addr, true_addr);
	AllocId funcId = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, b);
	VmReg[] res;

	res = c.call(funcId, VmReg(0));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(10));
	assert(res[0] == VmReg(1));

	// branch on pointer
	res = c.call(funcId, VmReg(funcId, 0));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(funcId, 10));
	assert(res[0] == VmReg(1));
}


@VmTest
void test_mov_0(ref VmTestContext c) {
	// Test mov of non-pointer
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId, VmReg(0), VmReg(42));
	assert(res[0] == VmReg(42));
}

@VmTest
void test_mov_1(ref VmTestContext c) {
	// Test mov of pointer from parameter to result
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId, VmReg(0), VmReg(funcId));
	assert(res[0] == VmReg(funcId));
}

@VmTest
void test_mov_2(ref VmTestContext c) {
	// Test mov of pointer with offset
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId, VmReg(0), VmReg(funcId, 42));
	assert(res[0] == VmReg(funcId, 42));
}

@VmTest
void test_mov_3(ref VmTestContext c) {
	// Test mov of non-pointer from uninitialized local to result
	// TODO: This may be either catched during validation, or we could have a bit per register and check it
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId, VmReg(0));
}


@VmTest
void test_cmp_0(ref VmTestContext c) {
	// Test cmp OOB condition
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(cast(VmBinCond)(VmBinCond.max+1), 0, 1, 2);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(0.NumResults, 0.NumRegParams, 0.NumStackParams, b);
	c.callFail(funcId);
	assert(c.vm.status == VmStatus.ERR_COND_OOB);
}


@VmTest
void test_cmp_4(ref VmTestContext c) {
	// Test cmp.m64.eq
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.m64_eq, 0, 0, 1);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId memId2 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res;

	// ptr is null
	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(0));

	// ptr is not null
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 10));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 20));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId2, 10));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId2, 20));
	assert(res[0] == VmReg(0));
}

@VmTest
void test_cmp_5(ref VmTestContext c) {
	// Test cmp.m64.ne
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.m64_ne, 0, 0, 1);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId memId2 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res;

	// ptr is null
	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(1));

	// ptr is not null
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 10));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 20));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId2, 10));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId2, 20));
	assert(res[0] == VmReg(1));
}

@VmTest
void test_cmp_6(ref VmTestContext c) {
	// Test cmp.u64.gt
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.u64_gt, 0, 0, 1);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res;

	// ptr is null
	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(20), VmReg(10));
	assert(res[0] == VmReg(1));

	// ptr is not null
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 10));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 20));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(memId1, 20), VmReg(memId1, 10));
	assert(res[0] == VmReg(1));
}

@VmTest
void test_cmp_7(ref VmTestContext c) {
	// Test cmp.u64.ge
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.u64_ge, 0, 0, 1);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res;

	// ptr is null
	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(20), VmReg(10));
	assert(res[0] == VmReg(1));

	// ptr is not null
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 10));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(memId1, 10), VmReg(memId1, 20));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(memId1, 20), VmReg(memId1, 10));
	assert(res[0] == VmReg(1));
}

@VmTest
@VmTestParam(TestParamId.user, [VmBinCond.u64_gt, VmBinCond.u64_ge])
void test_cmp_8(ref VmTestContext c) {
	// Test cmp.u64.gt/ge different pointers
	VmBinCond cond = cast(VmBinCond)c.test.getParam(TestParamId.user);
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(cond, 0, 0, 1);
	b.emit_trap();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId memId2 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	b.emit_cmp(cond, 0, 0, 1);
	b.emit_trap();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	c.callFail(funcId, VmReg(memId1, 10), VmReg(memId1, 10));
	assert(c.vm.status == VmStatus.ERR_CMP_REQUIRES_NO_PTR);
	c.callFail(funcId, VmReg(memId1, 10), VmReg(10));
	assert(c.vm.status == VmStatus.ERR_CMP_REQUIRES_NO_PTR);
	c.callFail(funcId, VmReg(10), VmReg(memId1, 10));
	assert(c.vm.status == VmStatus.ERR_CMP_REQUIRES_NO_PTR);
}

@VmTest
void test_cmp_10(ref VmTestContext c) {
	// Test cmp.s64.gt
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.s64_gt, 0, 0, 1);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res;

	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(20), VmReg(10));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(-20), VmReg(-10));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(-20), VmReg(-20));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(-10), VmReg(-20));
	assert(res[0] == VmReg(1));
}

@VmTest
void test_cmp_11(ref VmTestContext c) {
	// Test cmp.s64.ge
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_cmp(VmBinCond.s64_ge, 0, 0, 1);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res;

	res = c.call(funcId, VmReg(10), VmReg(10));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(20), VmReg(10));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(-20), VmReg(-10));
	assert(res[0] == VmReg(0));
	res = c.call(funcId, VmReg(-20), VmReg(-20));
	assert(res[0] == VmReg(1));
	res = c.call(funcId, VmReg(-10), VmReg(-20));
	assert(res[0] == VmReg(1));
}

@VmTest
void test_cmp_12(ref VmTestContext c) {
	// Test cmp.f32
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_mov(4, 0);
	b.emit_mov(5, 1);
	b.emit_cmp(VmBinCond.f32_gt, 0, 4, 5);
	b.emit_cmp(VmBinCond.f32_ge, 1, 4, 5);
	b.emit_cmp(VmBinCond.f32_gt, 2, 4, 5);
	b.emit_cmp(VmBinCond.f32_ge, 3, 4, 5);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(4.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	b.emit_mov(4, 0);
	b.emit_mov(5, 1);
	b.emit_cmp(VmBinCond.f64_gt, 0, 4, 5);
	b.emit_cmp(VmBinCond.f64_ge, 1, 4, 5);
	b.emit_cmp(VmBinCond.f64_gt, 2, 4, 5);
	b.emit_cmp(VmBinCond.f64_ge, 3, 4, 5);
	b.emit_ret();
	AllocId memId1 = c.genericMemAlloc(MemoryKind.heap_mem, SizeAndAlign(8, 1));
	AllocId funcId = c.vm.addFunction(4.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	b.emit_add_i64(0, 0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId, VmReg(10), VmReg(20));
	assert(res[0] == VmReg(30));
}

@VmTest
void test_add_i64_1(ref VmTestContext c) {
	// Test add_i64 ptr + number
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 0, 1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId, VmReg(funcId, 10), VmReg(20));
	assert(res[0] == VmReg(funcId, 30));
}

@VmTest
void test_add_i64_2(ref VmTestContext c) {
	// Test add_i64 ptr + ptr
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	c.callFail(funcId, VmReg(funcId, 10), VmReg(funcId, 20));
	assert(c.vm.status == VmStatus.ERR_PTR_SRC1);
}

@VmTest
void test_add_i64_3(ref VmTestContext c) {
	// Test add_i64 num + ptr
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_add_i64(0, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	c.callFail(funcId, VmReg(10), VmReg(funcId, 20));
	assert(c.vm.status == VmStatus.ERR_PTR_SRC1);
}


@VmTest
void test_const_s8_0(ref VmTestContext c) {
	// Test const_s8
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_const_s8(0, -1);
	b.emit_const_s8(1,  1);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(2.NumResults, 0.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId);
	assert(res[0] == VmReg(-1));
	assert(res[1] == VmReg( 1));
}


@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.load_m8, VmOpcode.load_m16, VmOpcode.load_m32, VmOpcode.load_m64])
void test_load_mXX_2(ref VmTestContext c) {
	// Test load_mXX src pointer undefined
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);
	c.callFail(funcId, VmReg(0), VmReg(memId, 8));
	assert(c.vm.status == VmStatus.ERR_LOAD_OOB);
}

static if (SANITIZE_UNINITIALIZED_MEM)
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
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	static if (SANITIZE_UNINITIALIZED_MEM) {
		c.vm.markInitialized(memId, 0, 16);  // make memory initialized
	}
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 0);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, b);

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
	static if (SANITIZE_UNINITIALIZED_MEM) {
		c.vm.markInitialized(memId, 0, 16);  // make memory initialized
	}
	c.memWritePtr(memId, 0, memId);

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 0);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, b);

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
	}
}


@VmTest
@VmTestParam(TestParamId.instr, [VmOpcode.store_m8, VmOpcode.store_m16, VmOpcode.store_m32, VmOpcode.store_m64])
void test_store_mXX_2(ref VmTestContext c) {
	// Test store_mXX dst pointer undefined
	VmOpcode op = cast(VmOpcode)c.test.getParam(TestParamId.instr);
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(op, 0, 1);
	b.emit_trap();
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);
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
	b.emit_binop(store_op, 0, 1);
	b.emit_binop(load_op, 0, 0);
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);

	foreach(offset; 0..9) {
		VmReg[] res = c.call(funcId, VmReg(memId, offset), VmReg(value));
		static if (SANITIZE_UNINITIALIZED_MEM) {
			// should not init unrelated bytes
			assert(c.countAllocInitBits(memId) == size);
		}
		assert(res[0] == VmReg(value & sizeMask));

		static if (SANITIZE_UNINITIALIZED_MEM) {
			// mark whole allocation as uninitialized
			c.setAllocInitBits(memId, false);
		}
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
	AllocId funcId = c.vm.addFunction(0.NumResults, 2.NumRegParams, 0.NumStackParams, b);

	foreach(offset; 1..c.vm.ptrSize.inBytes) {
		c.callFail(funcId, VmReg(memId, offset), VmReg(memId));
		assert(c.vm.status == VmStatus.ERR_STORE_PTR_UNALIGNED);

		static if (SANITIZE_UNINITIALIZED_MEM) {
			// memory was not touched by unsuccessful store
			assert(c.countAllocInitBits(memId) == 0);
		}
	}
}

@VmTest
@VmTestParam(TestParamId.memory, [MemoryKind.heap_mem, MemoryKind.stack_mem, MemoryKind.static_mem])
void test_store_mXX_8(ref VmTestContext c) {
	// Test store_mXX of pointers to aligned address
	MemoryKind memKind = cast(MemoryKind)c.test.getParam(TestParamId.memory);
	AllocId memId = c.genericMemAlloc(memKind, SizeAndAlign(8, 1));

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_store_ptr(c.vm.ptrSize, 0, 0); // store memId
	b.emit_load_ptr(c.vm.ptrSize, 0, 0); //   load memId
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 2.NumRegParams, 0.NumStackParams, b);

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
	b.emit_store_ptr(c.vm.ptrSize, 0, 1); // store memId1
	b.emit_store_ptr(c.vm.ptrSize, 0, 2); // store memId2 (overwrites memId1)
	b.emit_load_ptr(c.vm.ptrSize, 0, 0);  //  load memId2
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 3.NumRegParams, 0.NumStackParams, b);

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
	b.emit_store_ptr(c.vm.ptrSize, 0, 1); // store memId
	b.emit_store_ptr(c.vm.ptrSize, 0, 2); // store 0
	b.emit_load_ptr(c.vm.ptrSize, 0, 0);  //  load 0
	b.emit_ret();
	AllocId funcId = c.vm.addFunction(1.NumResults, 3.NumRegParams, 0.NumStackParams, b);

	VmReg[] res = c.call(funcId, VmReg(memId), VmReg(memId), VmReg(0));
	assert(res[0] == VmReg(0));
}


static extern(C) void externPrint(ref VmState state, void* userData) {
	writeln(state.regs[0]);
}


@VmTest
void test_call_0(ref VmTestContext c) {
	// External function call
	static extern(C) void externFunc(ref VmState state, void* userData) {
		assert(state.regs[0] == VmReg(10));
		state.regs[0] = VmReg(42);
	}

	AllocId extFuncId = c.vm.addExternalFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, &externFunc);

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_const_s8(0, 10);
	b.emit_call(0, 1, extFuncId.index);
	b.emit_ret();

	AllocId funcId = c.vm.addFunction(1.NumResults, 0.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId);
	assert(res[0] == VmReg(42));
}

@VmTest
void test_call_1(ref VmTestContext c) {
	// Bytecode function call

	AllocId funcA = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, Array!u8.init);
	AllocId funcB = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, Array!u8.init);

	// u64 a(u64 number) {
	//     return b(number) + 10;
	// }
	CodeBuilder a = CodeBuilder(c.vm.allocator);
	a.emit_call(0, 1, funcB.index);
	a.emit_const_s8(1, 10);
	a.emit_add_i64(0, 0, 1);
	a.emit_ret();

	c.vm.functions[funcA.index].code = a.code;

	// u64 b(u64 number) {
	//     return number + 42;
	// }
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_const_s8(1, 42);
	b.emit_add_i64(0, 0, 1);
	b.emit_ret();

	c.vm.functions[funcB.index].code = b.code;

	VmReg[] res = c.call(funcA, VmReg(5));
	assert(res[0] == VmReg(57));
}


@VmTest
void test_tail_call_0(ref VmTestContext c) {
	// External function call
	static extern(C) void externFunc(ref VmState state, void* userData) {
		assert(state.regs[0] == VmReg(10));
		state.regs[0] = VmReg(42);
	}

	AllocId extFuncId = c.vm.addExternalFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, &externFunc);

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_const_s8(0, 10);
	b.emit_tail_call(0, extFuncId.index);
	b.emit_ret();

	AllocId funcId = c.vm.addFunction(1.NumResults, 0.NumRegParams, 0.NumStackParams, b);
	VmReg[] res = c.call(funcId);
	assert(res[0] == VmReg(42));
}

@VmTest
void test_tail_call_1(ref VmTestContext c) {
	// Bytecode function tail call

	AllocId funcA = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, Array!u8.init);
	AllocId funcB = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, Array!u8.init);

	// u64 a(u64 number) {
	//     return b(number);
	// }
	CodeBuilder a = CodeBuilder(c.vm.allocator);
	a.emit_tail_call(0, funcB.index);

	c.vm.functions[funcA.index].code = a.code;

	// u64 b(u64 number) {
	//     return number + 42;
	// }
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_const_s8(1, 42);
	b.emit_add_i64(0, 0, 1);
	b.emit_ret();

	c.vm.functions[funcB.index].code = b.code;

	VmReg[] res = c.call(funcA, VmReg(5));
	assert(res[0] == VmReg(47));
}


@VmTest
@VmTestIgnore
@VmTestOnly
@TestPtrSize64
void bench_0(ref VmTestContext c) {
	// Benchmark fib

	AllocId funcId = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, Array!u8.init);

	// u64 fib(u64 number) {
	//     if (number <= 1) return number;
	//     return fib(number-1) + fib(number-2);
	// }
	// r0: result
	// r0: number
	// r1: temp1
	// r2: temp2
	// r3: callee result
	// r3: callee number
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	// if (number <= 1)
	b.emit_const_s8(1, 1);
	b.emit_cmp(VmBinCond.s64_ge, 1, 1, 0);
	u32 patch_addr1 = b.emit_branch(1);
	// fib(number-1)
	b.emit_const_s8(2, 1);
	b.emit_sub_i64(3, 0, 2);
	b.emit_call(3, 1, funcId.index);
	b.emit_mov(1, 3);
	// fib(number-2)
	b.emit_const_s8(2, 2);
	b.emit_sub_i64(3, 0, 2);
	b.emit_call(3, 1, funcId.index);
	b.emit_mov(2, 3);
	// fib(number-1) + fib(number-2)
	b.emit_add_i64(0, 1, 2);
	// return number
	b.patch_rip(patch_addr1, b.next_addr);
	b.emit_ret();

	c.vm.functions[funcId.index].code = b.code;

	//disasm(stdoutSink, b[]);

	VmReg[] res = c.call(funcId, VmReg(40));
	writefln("%s", res[0].as_u64);
	assert(res[0] == VmReg(102334155));
}


@VmTest
@VmTestIgnore
@VmTestOnly
@TestPtrSize64
void bench_1(ref VmTestContext c) {
	// Benchmark fib (special opcodes)

	AllocId funcId = c.vm.addFunction(1.NumResults, 1.NumRegParams, 0.NumStackParams, Array!u8.init);

	// u64 fib(u64 number) {
	//     if (number <= 1) return number;
	//     return fib(number-1) + fib(number-2);
	// }
	// r0: result
	// r0: number
	// r1: temp1
	// r2: temp2
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	// if (number <= 1)
	//b.emit_const_s8(1, 1);
	u32 patch_addr1 = b.emit_branch_gt_imm8(0, 1);
	b.emit_ret();
	// fib(number-1)
	b.patch_rip(patch_addr1, b.next_addr);
	b.emit_add_i64_imm8(1, 0, -1);
	b.emit_call(1, 1, funcId.index);
	// fib(number-2)
	b.emit_add_i64_imm8(2, 0, -2);
	b.emit_call(2, 1, funcId.index);
	// fib(number-1) + fib(number-2)
	b.emit_add_i64(0, 1, 2);
	// return number
	b.emit_ret();

	c.vm.functions[funcId.index].code = b.code;

	//disasm(stdoutSink, b[]);

	VmReg[] res = c.call(funcId, VmReg(40));
	writefln("%s", res[0].as_u64);
	assert(res[0] == VmReg(102334155));
}
