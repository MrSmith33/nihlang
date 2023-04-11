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

	// Sets vm.status
	private VmFunction* setupCall(AllocId funcId, u8 arg0_idx, VmReg[] regParams) {
		vm.status = VmStatus.RUNNING;

		if(funcId.index >= vm.functions.length) {
			panic("Invalid function index (%s), only %s functions exist",
				funcId.index, vm.functions.length);
		}
		if(funcId.kind != MemoryKind.func_id) {
			panic("Invalid AllocId kind, expected func_id, got %s",
				memoryKindString[funcId.kind]);
		}
		VmFunction* func = &vm.functions[funcId.index];
		if(regParams.length < func.numRegParams) {
			panic("Invalid number of register parameters provided, expected at least %s, got %s",
				func.numRegParams, regParams.length);
		}

		// set register parameters (skip excess register parameters)
		foreach(i; arg0_idx..arg0_idx+func.numRegParams) {
			vm.regs[i] = regParams[i];
		}

		// Sets vm.status
		instr_call_impl(vm, FuncId(funcId.index), arg0_idx);

		return func;
	}

	// Takes exactly VmFunction.numStackParams arguments from the stack
	VmReg[] call(AllocId funcId, VmReg[] regParams...) {
		VmFunction* func = setupCall(funcId, 0, regParams);
		vm.run();
		// vm.runVerbose(sink);

		if (vm.status.isError) {
			sink("  ---\n");
			sink.formattedWrite("  Test %s failed\n", test.name);
			sink("  Function expected to finish successfully\n");
			sink("  ");
			vmFormatError(vm, sink);
			u32 ipCopy = vm.ip;
			sink("\n  ---\n  ");
			disasmOne(sink, vm.functions[vm.func].code[], ipCopy);
			sink("\n  ---\n");
			panic("  Function expected to finish successfully");
		}

		return vm.registers[0..func.numResults];
	}

	void callFail(AllocId funcId, VmReg[] regParams...) {
		setupCall(funcId, 0, regParams);
		vm.run();
		// vm.runVerbose(sink);
		if (!vm.status.isError) {
			panic("Function expected to trap");
		}
		//vm.format_vm_error(sink);
		//sink("\n  ---\n  ");
		//u32 ipCopy = vm.frames.back.ip;
		//disasmOne(sink, vm.functions[vm.frames.back.func].code[], ipCopy);
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
		final switch(kind) with(MemoryKind) {
			case stack_mem: return vm.pushStackAlloc(sizeAlign);
			case heap_mem, static_mem: return vm.memories[kind].allocate(*vm.allocator, sizeAlign, kind);
			case func_id: assert(false, "Cannot allocate function id");
		}
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

	static if (SANITIZE_UNINITIALIZED_MEM)
	void setAllocInitBits(AllocId allocId, bool value) {
		Memory* mem = &vm.memories[allocId.kind];
		Allocation* alloc = &mem.allocations[allocId.index];
		mem.markInitBits(alloc.offset, alloc.size, value);
	}

	static if (SANITIZE_UNINITIALIZED_MEM)
	size_t countAllocInitBits(AllocId allocId) {
		Memory* mem = &vm.memories[allocId.kind];
		Allocation* alloc = &mem.allocations[allocId.index];
		size_t* initBits = cast(size_t*)&mem.initBitmap.front();
		return popcntBitRange(initBits, alloc.offset, alloc.offset + alloc.size);
	}
}
