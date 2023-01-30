/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.vm.tests.infra.test;

import vox.lib;
import vox.vm;

// attribute
enum VmTest;

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

	u8 ptrSizeFlags;
	u8 flags;
	bool attrPtrSize32;
	bool attrPtrSize64;

	foreach (attr; __traits(getAttributes, test)) {
		static if (is(typeof(attr) == TestAtrib)) {
			final switch(attr) with(TestAtrib) {
				case ptrSize32:
					attrPtrSize32 = true;
					ptrSizeFlags |= TestFlags.ptrSize32;
					break;
				case ptrSize64:
					attrPtrSize64 = true;
					ptrSizeFlags |= TestFlags.ptrSize64;
					break;
			}
		}
	}

	if (attrPtrSize32 == attrPtrSize64) {
		// test both if nothing is specified or both specified
		Test t1 = {
			test_handler : &test,
			flags : flags | TestFlags.ptrSize32,
		};
		tests.put(allocator, t1);

		Test t2 = {
			test_handler : &test,
			flags : flags | TestFlags.ptrSize64,
		};
		tests.put(allocator, t2);
	} else {
		Test t = {
			test_handler : &test,
			flags : flags | ptrSizeFlags,
		};
		tests.put(allocator, t);
	}
}

struct Test {
	@nogc nothrow:
	void function(ref VmTestContext) test_handler;
	u8 flags; // set of TestFlags

	u8 ptrSize() {
		if (flags & TestFlags.ptrSize32) return 4;
		return 8;
	}
}

enum TestAtrib : u8 {
	ptrSize32 = 1,
	ptrSize64 = 2,
}

// Can be an attribute on the test case
enum TestFlags : u8 {
	ptrSize32 = 1 << 0,
	ptrSize64 = 1 << 1,
}

struct VmTestContext {
	@nogc nothrow:
	VmState* vm;
	SinkDelegate sink;

	VmReg[] call(AllocId funcId, VmReg[] params...) {
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

	AllocId staticAlloc(SizeAndAlign sizeAlign) {
		return vm.memories[MemoryKind.static_mem].allocate(*vm.allocator, sizeAlign, MemoryKind.static_mem);
	}

	AllocId heapAlloc(SizeAndAlign sizeAlign) {
		return vm.memories[MemoryKind.heap_mem].allocate(*vm.allocator, sizeAlign, MemoryKind.heap_mem);
	}

	AllocId stackAlloc(SizeAndAlign sizeAlign) {
		return vm.memories[MemoryKind.stack_mem].allocate(*vm.allocator, sizeAlign, MemoryKind.stack_mem);
	}
}
