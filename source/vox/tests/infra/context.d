/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.tests.infra.context;

import vox.lib;
import vox.tests.infra;

@nogc nothrow:

struct ITestContext {
	@nogc nothrow:

	void* instance;
	@nogc nothrow void function(ref TestInstance) runTestPtr;
	@nogc nothrow void function(ref VoxAllocator, TestDefinition, ref Array!MakerParam) addTestInstanceParamsPtr;

	void runTest(ref TestInstance test) {
		@nogc nothrow void delegate(ref TestInstance) fun;
		fun.ptr = instance;
		fun.funcptr = runTestPtr;
		fun(test);
	}

	void addTestInstanceParams(
		ref VoxAllocator allocator,
		TestDefinition def,
		ref Array!MakerParam parameters) {
		@nogc nothrow void delegate(ref VoxAllocator, TestDefinition, ref Array!MakerParam) fun;
		fun.ptr = instance;
		fun.funcptr = addTestInstanceParamsPtr;
		fun(allocator, def, parameters);
	}
}

mixin template TestContextUtils() {
	@nogc nothrow:

	ITestContext toInterface() {
		ITestContext res = {
			instance : &this,
			runTestPtr : (&this.runTest).funcptr,
			addTestInstanceParamsPtr : (&this.addTestInstanceParams).funcptr,
		};
		return res;
	}

	void addTestInstanceParams(
		ref VoxAllocator allocator,
		TestDefinition def,
		ref Array!MakerParam parameters) {}
}

// For tests that don't really need a special context
struct SimpleTestContext {
	mixin TestContextUtils;

	@nogc nothrow:

	SinkDelegate sink;
	TestInstance test;
	VoxAllocator* allocator;

	this(VoxAllocator* allocator, SinkDelegate _sink) {
		this.allocator = allocator;
		sink = _sink;
	}

	void runTest(ref TestInstance _test) {
		test = _test;
		test.test_handler(&this);
	}
}
