/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.tests.infra.test;

import vox.lib;
import vox.types;
import vox.tests.infra;

@nogc nothrow:

struct TestSuite {
	@nogc nothrow:
	Array!ITestContext contexts;
	Array!TestDefinition definitions;
	// test permutations
	Array!TestInstance tests;
	TestFilter filter;

	u8 registerContext(ref VoxAllocator allocator, ITestContext context) {
		foreach(i, c; contexts) {
			if (c == context) {
				return cast(u8)i;
			}
		}
		auto contextIndex = cast(u8)contexts.length;
		assert(contextIndex == contexts.length, "Out of context space");
		contexts.put(allocator, context);
		return contextIndex;
	}
}

alias TestHandler = @nogc nothrow void function(void*);

struct TestDefinition {
	@nogc nothrow:
	string name;
	// File where the test is located
	string file;
	// When test has @"" attribute
	string source;
	// Line in a file where the test is located
	u32 line;
	// Index into TestSuite.definitions
	u32 index;
	// @TestPtrSize32
	bool attrPtrSize32;
	// @TestPtrSize64
	bool attrPtrSize64;
	// @TestOnly
	bool onlyThis;
	// @TestIgnore
	bool ignore;
	// Index into TestSuite.contexts
	u8 contextIndex;

	// @TestParam attributes attached to a test
	Array!TestParam parameters;
	// Actual test code, called by a test runner for each test instance
	TestHandler test_handler;
}

struct TestInstance {
	@nogc nothrow:

	TestHandler test_handler;
	Array!Param parameters;
	string name;
	// Index into TestSuite.definitions
	u32 definition;
	// index of permutation within this test 0..n
	u32 permutation;
	// Index into TestSuite.tests
	u32 index;
	// Index into TestSuite.contexts
	u8 contextIndex;

	PtrSize ptrSize() {
		return cast(PtrSize)getParam(TestParamId.ptr_size);
	}

	u32 getParam(u8 id) {
		foreach(param; parameters) {
			if (param.id == id) return param.value;
		}
		panic("No parameter with such id");
	}

	static struct Param {
		u8 id;
		u32 value;
	}
}

struct TestFilter {
	@nogc nothrow:

	bool enabled = false;
	bool disabled() => !enabled;
	bool shouldRun(ref TestInstance test) {
		return definition == test.definition;
	}

	u32 definition;
}
