/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.vm.tests.infra.test;

import vox.lib;
import vox.vm;

@nogc nothrow:

// attribute
enum VmTest;
struct VmTestParam {
	TestParamId id;
	u32[] values;
}

void collectTests(alias M)(ref VoxAllocator allocator, ref Array!Test tests) {
	import std.traits : hasUDA;
	foreach(m; __traits(allMembers, M))
	{
		alias member = __traits(getMember, M, m);
		static if (hasUDA!(member, VmTest)) {
			makeTest!member(allocator, tests);
		}
	}
}

void makeTest(alias test)(ref VoxAllocator allocator, ref Array!Test tests) {
	Test res;

	bool attrPtrSize32;
	bool attrPtrSize64;
	u32 numPermutations = 1;

	static struct Param {
		TestParamId id;
		Array!u32 values;
		u32 currentIndex;
	}

	Array!Param parameters;

	foreach (attr; __traits(getAttributes, test)) {
		static if (is(typeof(attr) == TestAtrib)) {
			final switch(attr) with(TestAtrib) {
				case ptrSize32:
					attrPtrSize32 = true;
					break;
				case ptrSize64:
					attrPtrSize64 = true;
					break;
			}
		} else static if (is(typeof(attr) == VmTestParam)) {
			Array!u32 values;
			values.reserve(allocator, attr.values.length);
			numPermutations *= attr.values.length;
			foreach(val; attr.values) {
				values.put(allocator, val);
			}
			// skip empty parameters
			if (values.length > 0) {
				parameters.put(allocator, Param(attr.id, values));
			}
		}
	}

	// Add ptr sizes
	Array!u32 ptr_size_values;
	if (attrPtrSize32 != attrPtrSize64) {
		ptr_size_values.put(allocator, attrPtrSize32 ? 4 : 8);
	} else {
		ptr_size_values.put(allocator, 4, 8);
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
			test_handler : &test,
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

struct Test {
	@nogc nothrow:
	void function(ref VmTestContext) test_handler;
	Array!Param parameters;

	u8 ptrSize() {
		return cast(u8)getParam(TestParamId.ptr_size);
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

enum TestParamId : u8 {
	ptr_size,
	instr,
	memory,
}

enum TestAtrib : u8 {
	ptrSize32 = 1,
	ptrSize64 = 2,
}

struct VmTestContext {
	@nogc nothrow:
	VmState* vm;
	SinkDelegate sink;
	Test test;

	private VmFunction* setupCall(AllocId funcId, VmReg[] params) {
		if(funcId.index >= vm.functions.length) {
			panic("Invalid function index (%s), only %s functions exist",
				funcId.index, vm.functions.length);
		}
		if(funcId.kind != MemoryKind.func_id) {
			panic("Invalid AllocId kind, expected func_id, got %s",
				memoryKindString[funcId.kind]);
		}
		VmFunction* func = &vm.functions[funcId.index];
		if(func.numParameters != params.length) {
			panic("Invalid number of parameters provided, expected %s, got %s",
				func.numParameters, params.length);
		}

		vm.pushRegisters(func.numResults);
		vm.pushRegisters(params);

		vm.beginCall(funcId);

		return func;
	}

	VmReg[] call(AllocId funcId, VmReg[] params...) {
		VmFunction* func = setupCall(funcId, params);
		vm.run();
		// vm.runVerbose(sink);

		if (vm.status != VmStatus.OK) {
			u32 ipCopy = vm.frames.back.ip;
			disasmOne(sink, vm.frames.back.func.code[], ipCopy);
			sink("Error: ");
			vm.format_vm_error(sink);
			panic("Function expected to finish successfully");
		}

		if(vm.registers.length != func.numResults) panic("Function with %s results returned %s results.", func.numResults, vm.registers.length);

		return vm.registers[];
	}

	void callFail(AllocId funcId, VmReg[] params...) {
		setupCall(funcId, params);
		vm.run();
		if (vm.status == VmStatus.OK) {
			panic("Function expected to trap");
		}
	}

	AllocId staticAlloc(SizeAndAlign sizeAlign) {
		return vm.memories[MemoryKind.static_mem].allocate(*vm.allocator, sizeAlign, MemoryKind.static_mem);
	}

	AllocId heapAlloc(SizeAndAlign sizeAlign) {
		return vm.memories[MemoryKind.heap_mem].allocate(*vm.allocator, sizeAlign, MemoryKind.heap_mem);
	}

	AllocId stackAlloc(SizeAndAlign sizeAlign) {
		return vm.memories[MemoryKind.stack_mem].allocate(*vm.allocator, sizeAlign, MemoryKind.stack_mem);
	}

	AllocId genericMemAlloc(MemoryKind kind, SizeAndAlign sizeAlign) {
		return vm.memories[kind].allocate(*vm.allocator, sizeAlign, kind);
	}
}
