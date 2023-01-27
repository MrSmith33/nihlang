/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.vm.tests.infra.test;

import vox.lib;
import vox.vm;

struct VmTestContext {
	@nogc nothrow:
	VmState* vm;

	VmRegister[] call(scope SinkDelegate sink, AllocationId funcId, VmRegister[] params...) {
		if(funcId.index >= vm.functions.length) panic("Invalid function index (%s), only %s functions exist", funcId.index, vm.functions.length);
		if(funcId.kind != MemoryKind.func_id) panic("Invalid AllocationId kind, expected func_id, got %s", memoryKindString[funcId.kind]);
		VmFunction* func = &vm.functions[funcId.index];
		if(func.numParameters != params.length) panic("Invalid number of parameters provided, expected %s, got %s", func.numParameters, params.length);

		vm.pushRegisters(func.numResults);
		vm.pushRegisters(params);

		vm.beginCall(funcId);

		vm.run(sink);

		if (vm.status != VmStatus.OK) panic("Function expected to finish successfully");

		if(vm.registers.length != func.numResults) panic("Function with %s results returned %s results.", func.numResults, vm.registers.length);

		return vm.registers[];
	}

	AllocationId staticAlloc(SizeAndAlign sizeAlign) {
		return vm.memories[MemoryKind.static_mem].allocate(*vm.allocator, sizeAlign, MemoryKind.static_mem);
	}

	AllocationId heapAlloc(SizeAndAlign sizeAlign) {
		return vm.memories[MemoryKind.heap_mem].allocate(*vm.allocator, sizeAlign, MemoryKind.heap_mem);
	}

	AllocationId stackAlloc(SizeAndAlign sizeAlign) {
		return vm.memories[MemoryKind.stack_mem].allocate(*vm.allocator, sizeAlign, MemoryKind.stack_mem);
	}
}
