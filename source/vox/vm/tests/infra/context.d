/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.vm.tests.infra.context;

import vox.lib;
import vox.vm;
import vox.vm.tests.infra;

@nogc nothrow:

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

	void clearStack() {
		vm.registers.clear;
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

	// Assumes that non-pointer data was already written
	void memWritePtr(AllocId dstMem, u32 offset, AllocId ptrVal) {
		Memory* mem = &vm.memories[dstMem.kind];
		Allocation* alloc = &mem.allocations[dstMem.index];
		memWritePtr(mem, alloc, offset, ptrVal);
	}

	void memWritePtr(Memory* mem, Allocation* alloc, u32 offset, AllocId ptrVal) {
		if (ptrVal.isDefined) {
			vm.pointerPut(mem, alloc, offset, ptrVal);
		} else {
			vm.pointerRemove(mem, alloc, offset);
		}
	}
}
