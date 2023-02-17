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
	VmState vm;
	SinkDelegate sink;
	Test test;

	this(ref VoxAllocator allocator, SinkDelegate _sink) {
		vm.allocator = &allocator;
		vm.readWriteMask = MemFlags.heap_RW | MemFlags.stack_RW | MemFlags.static_RW;
		vm.ptrSize = PtrSize._32;

		enum static_bytes = 64*1024;
		enum heap_bytes = 64*1024;
		enum stack_bytes = 64*1024;
		vm.reserveMemory(static_bytes, heap_bytes, stack_bytes);

		sink = _sink;
	}

	// Called before each test
	void prepareForTest(ref Test _test) {
		vm.reset;
		test = _test;
		vm.ptrSize = test.ptrSize;
		vm.readWriteMask = MemFlags.heap_RW | MemFlags.stack_RW | MemFlags.static_RW;
	}

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
			sink("  ---\n");
			sink.formattedWrite("  Test %s failed\n", test.name);
			sink("  Function expected to finish successfully\n");
			sink("  ");
			vmFormatError(vm, sink);
			u32 ipCopy = vm.frameIp;
			sink("\n  ---\n  ");
			disasmOne(sink, vm.functions[vm.frameFuncIndex].code[], ipCopy);
			sink("  ---\n");
			panic("  Function expected to finish successfully");
		}

		if(vm.registers.length != func.numResults) panic("Function with %s results returned %s results.", func.numResults, vm.registers.length);

		return vm.registers[];
	}

	void callFail(AllocId funcId, VmReg[] params...) {
		setupCall(funcId, params);
		vm.run();
		//vm.runVerbose(sink);
		if (vm.status == VmStatus.OK) {
			panic("Function expected to trap");
		}
		//vm.format_vm_error(sink);
		//sink("\n  ---\n  ");
		//u32 ipCopy = vm.frames.back.ip;
		//disasmOne(sink, vm.functions[vm.frames.back.funcIndex].code[], ipCopy);
		//sink("  ---\n");
		clearStack;
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

	void setAllocInitBits(AllocId allocId, bool value) {
		Memory* mem = &vm.memories[allocId.kind];
		Allocation* alloc = &mem.allocations[allocId.index];
		mem.markInitBits(alloc.offset, alloc.size, value);
	}

	size_t countAllocInitBits(AllocId allocId) {
		Memory* mem = &vm.memories[allocId.kind];
		Allocation* alloc = &mem.allocations[allocId.index];
		size_t* initBits = cast(size_t*)&mem.initBitmap.front();
		return popcntBitRange(initBits, alloc.offset, alloc.offset + alloc.size);
	}
}
