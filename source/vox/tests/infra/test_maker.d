/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.tests.infra.test_maker;

import vox.lib;
import vox.types;
import vox.tests.infra;

@nogc nothrow:

void collectTests(alias M)(ref VoxAllocator allocator, ref TestSuite suite) {
	foreach(m; __traits(allMembers, M))
	{
		alias member = __traits(getMember, M, m);
		foreach (attr; __traits(getAttributes, member)) {
			static if (is(attr == Test)) {
				suite.definitions.put(allocator, TestDefinition.init);
				gatherTestDefinition!member(allocator, suite.definitions.back);
				break;
			}
		}
	}
	foreach(i, ref d; suite.definitions) {
		d.index = cast(u32)i;
		makeTest(allocator, suite, d);
	}
}

// This must be as small as possible, otherwise compile times are to big
void gatherTestDefinition(alias test)(ref VoxAllocator allocator, ref TestDefinition def) {
	def.name = __traits(identifier, test);
	def.file = __traits(getLocation, test)[0];
	def.line = __traits(getLocation, test)[1];
	def.test_handler = cast(TestHandler)&test;
	foreach (attr; __traits(getAttributes, test)) {
		static if (is(attr == TestPtrSize32)) {
			def.attrPtrSize32 = true;
		} else static if (is(attr == TestPtrSize64)) {
			def.attrPtrSize64 = true;
		} else static if (is(attr == TestOnly)) {
			def.onlyThis = true;
		} else static if (is(attr == TestIgnore)) {
			def.ignore = true;
		} else static if (is(typeof(attr) == TestParam)) {
			static __gshared u32[] attr_values = attr.values;
			def.parameters.put(allocator, TestDefinition.Param(attr.id, attr_values));
		}
	}
}

void makeTest(ref VoxAllocator allocator, ref TestSuite suite, TestDefinition def) {
	if (def.ignore) return;

	if (def.onlyThis) {
		if (suite.filter.enabled) {
			auto otherDef = suite.definitions[suite.filter.definition];
			panic("TestOnly attribute found in multiple places:\n  %s at %s:%s\n  %s at %s:%s\n",
				otherDef.name, otherDef.file, otherDef.line,
				def.name, def.file, def.line);
		}
		suite.filter.definition = def.index;
		suite.filter.enabled = true;
	}

	u32 numPermutations = 1;

	static struct Param {
		u8 id;
		Array!u32 values;
		u32 currentIndex;
	}

	Array!Param parameters;
	scope(exit) parameters.free(allocator);

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
		Array!(TestInstance.Param) testParameters;
		testParameters.voidPut(allocator, parameters.length);
		foreach(i, ref param; parameters) {
			testParameters[i] = TestInstance.Param(param.id, param.values[param.currentIndex]);
			//writef(" (%s %s)", param.id, param.values[param.currentIndex]);
		}
		//writeln;

		TestInstance t = {
			name : def.name,
			definition : def.index,
			permutation : numPermutations - 1,
			index : suite.tests.length,
			test_handler : def.test_handler,
			parameters : testParameters,
		};
		suite.tests.put(allocator, t);

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
