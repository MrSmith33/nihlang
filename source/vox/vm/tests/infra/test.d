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
			tests.put(allocator, makeTest!member);
		}
	}
}

Test makeTest(alias test)() {
	return Test(&test);
}

struct Test {
	@nogc nothrow:
	void function(ref VmTestContext) tester;
}

struct VmTestContext {
	@nogc nothrow:
	VmState* vm;

	VmRegister[] call(scope SinkDelegate sink, AllocId funcId, VmRegister[] params...) {
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
