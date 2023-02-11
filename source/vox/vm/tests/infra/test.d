/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.vm.tests.infra.test;

import vox.lib;
import vox.vm;
import vox.vm.tests.infra;

@nogc nothrow:

struct TestSuite {
	Array!TestDefinition definitions;
	// test permutations
	Array!Test tests;
	TestFilter filter;
}

struct Test {
	@nogc nothrow:

	void function(ref VmTestContext) test_handler;
	Array!Param parameters;
	string name;
	// Index into TestSuite.definitions
	u32 definition;
	// index of permutation within this test 0..n
	u32 permutation;
	// Index into TestSuite.tests
	u32 index;

	PtrSize ptrSize() {
		return cast(PtrSize)getParam(TestParamId.ptr_size);
	}

	u32 getParam(TestParamId id) {
		foreach(param; parameters) {
			if (param.id == id) return param.value;
		}
		panic("No parameter with such id");
	}

	static struct Param {
		TestParamId id;
		u32 value;
	}
}

struct TestFilter {
	@nogc nothrow:

	bool enabled = false;
	bool shouldRun(ref Test test) {
		return definition == test.definition;
	}

	u32 definition;
}
