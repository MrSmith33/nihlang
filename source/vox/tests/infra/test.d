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
	Array!TestDefinition definitions;
	// test permutations
	Array!TestInstance tests;
	TestFilter filter;
}

alias TestHandler = @nogc nothrow void function(void*);

struct TestDefinition {
	@nogc nothrow:
	string name;
	string file;
	u32 line;
	u32 index;
	static struct Param {
		u8 id;
		u32[] values;
	}
	bool attrPtrSize32;
	bool attrPtrSize64;
	bool onlyThis;
	bool ignore;
	Array!Param parameters;
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
