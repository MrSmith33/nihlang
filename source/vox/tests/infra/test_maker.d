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

void collectTestDefinitions(alias M)(ref VoxAllocator allocator, ref TestSuite suite, u8 contextId) {
	foreach(m; __traits(allMembers, M))
	{
		alias member = __traits(getMember, M, m);
		foreach (attr; __traits(getAttributes, member)) {
			static if (is(attr == Test)) {
				suite.definitions.put(allocator, TestDefinition.init);
				gatherTestDefinition!member(allocator, suite.definitions.back, contextId);
				break;
			}
		}
	}
}

// This must be as small as possible, otherwise compile times are to big
void gatherTestDefinition(alias test)(ref VoxAllocator allocator, ref TestDefinition def, u8 contextId) {
	def.name = __traits(identifier, test);
	def.file = __traits(getLocation, test)[0];
	def.line = __traits(getLocation, test)[1];
	def.test_handler = cast(TestHandler)&test;
	def.contextIndex = contextId;
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
			def.parameters.put(allocator, TestParam(attr.id, attr_values));
		} else static if (is(typeof(attr) == string)) {
			def.source = attr;
		}
	}
}

void instantiateTests(ref VoxAllocator allocator, ref TestSuite suite) {
	foreach(i, ref d; suite.definitions) {
		d.index = cast(u32)i;
		instantiateTest(allocator, suite, d);
	}
}

static struct MakerParam {
	u8 id;
	Array!u32 values;
	u32 currentIndex;
}

void instantiateTest(ref VoxAllocator allocator, ref TestSuite suite, TestDefinition def) {
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

	ITestContext context = suite.contexts[def.contextIndex];

	u32 numPermutations = 1;

	Array!MakerParam parameters;
	scope(exit) parameters.free(allocator);

	context.addTestInstanceParams(allocator, def, parameters);

	// Calculate permutations for implicit parameters added by addTestInstanceParams
	foreach(ref p; parameters) {
		if (p.values.length > 0) {
			numPermutations *= p.values.length;
		}
	}

	// Calculate permutations for parameters added by the definition
	foreach(ref p; def.parameters) {
		// skip empty parameters
		if (p.values.length > 0) {
			numPermutations *= p.values.length;
			Array!u32 values;
			values.put(allocator, p.values);
			parameters.put(allocator, MakerParam(p.id, values));
		}
	}

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
			contextIndex : def.contextIndex,
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
