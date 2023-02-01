/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.vm.tests.infra.test_maker;

import vox.lib;
import vox.vm;
import vox.vm.tests.infra;

@nogc nothrow:

void collectTests(alias M)(ref VoxAllocator allocator, ref Array!Test tests) {
	import std.traits : hasUDA;
	Array!TestDefinition defs;
	foreach(m; __traits(allMembers, M))
	{
		alias member = __traits(getMember, M, m);
		static if (hasUDA!(member, VmTest)) {
			defs.put(allocator, TestDefinition.init);
			gatherTestDefinition!member(allocator, defs.back);
		}
	}
	foreach(ref d; defs) makeTest(allocator, tests, d);
}

// This must be as small as possible, otherwise compile times are to big
void gatherTestDefinition(alias test)(ref VoxAllocator allocator, ref TestDefinition def) {
	def.test_handler = &test;
	foreach (attr; __traits(getAttributes, test)) {
		static if (is(attr == TestPtrSize32)) {
			def.attrPtrSize32 = true;
		} else static if (is(attr == TestPtrSize64)) {
			def.attrPtrSize64 = true;
		} else static if (is(typeof(attr) == VmTestParam)) {
			static __gshared u32[] attr_values = attr.values;
			def.parameters.put(allocator, TestDefinition.Param(attr.id, attr_values));
		}
	}
}

struct TestDefinition {
	@nogc nothrow:
	static struct Param {
		TestParamId id;
		u32[] values;
	}
	bool attrPtrSize32;
	bool attrPtrSize64;
	Array!Param parameters;
	void function(ref VmTestContext) test_handler;
}

void makeTest(ref VoxAllocator allocator, ref Array!Test tests, TestDefinition def) {
	Test res;
	u32 numPermutations = 1;

	static struct Param {
		TestParamId id;
		Array!u32 values;
		u32 currentIndex;
	}

	Array!Param parameters;

	foreach(ref p; def.parameters) {
		// skip empty parameters
		if (p.values.length > 0) {
			numPermutations *= p.values.length;
			Array!u32 values;
			values.put(allocator, p.values);
			parameters.put(allocator, Param(p.id, values));
		}
	}

	// Add ptr sizes
	Array!u32 ptr_size_values;
	if (def.attrPtrSize32 != def.attrPtrSize64) {
		ptr_size_values.put(allocator, def.attrPtrSize32 ? PtrSize._32 : PtrSize._64);
	} else {
		ptr_size_values.put(allocator, PtrSize._32, PtrSize._64);
		numPermutations *= 2;
	}
	parameters.put(allocator, Param(TestParamId.ptr_size, ptr_size_values));

	//writefln("parameters.length %s numPermutations %s", parameters.length, numPermutations);
	//foreach(i, ref param; parameters) {
	//	writefln("  %s %s", param.id, param.values.length);
	//}

	// create all permutations
	while(numPermutations) {
		// gather parameters
		Array!(Test.Param) testParameters;
		testParameters.voidPut(allocator, parameters.length);
			foreach(i, ref param; parameters) {
			testParameters[i] = Test.Param(param.id, param.values[param.currentIndex]);
			//writef(" (%s %s)", param.id, param.values[param.currentIndex]);
		}
		//writeln;

		Test t = {
			test_handler : def.test_handler,
			parameters : testParameters,
		};
		tests.put(allocator, t);

		// increment
		foreach(ref param; parameters) {
			// treat each parameter as a digit in a number
			// increate this number by one, until we reach 0 again
			// each digit's max value is param.values.length-1
			if (param.currentIndex + 1 == param.values.length) {
				param.currentIndex = 0;
				// continue to the next digit
			} else {
				++param.currentIndex;
				break;
			}
		}
		--numPermutations;
	}
}
