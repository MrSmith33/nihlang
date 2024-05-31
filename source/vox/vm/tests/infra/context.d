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

	this(VoxAllocator* allocator, SinkDelegate _sink) {
		vm.allocator = allocator;

		enum static_bytes = 1*1024;
		enum heap_bytes = 1*1024;
		enum stack_bytes = 1*1024;

		// Set to 32 bit during reserve, so that pointer bitmaps cover both 32 and 64 bits
		vm.ptrSize = PtrSize._32;
		vm.reserveMemory(static_bytes, heap_bytes, stack_bytes);

		sink = _sink;
	}

	// Called before each test
	void prepareForTest(ref Test _test) {
		test = _test;
		vm.ptrSize = test.ptrSize;
		vm.memories[MemoryKind.static_mem].ptrSize = test.ptrSize;
		vm.memories[MemoryKind.heap_mem].ptrSize   = test.ptrSize;
		vm.memories[MemoryKind.stack_mem].ptrSize  = test.ptrSize;
		vm.resetMem;
		vm.resetState;
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

	private void printState() {
		sink("  ---\n  ");
		if (vm.ip < vm.functions[vm.func].code.length) {
			sink("  ---\n  ");
			u32 ipCopy = vm.ip;
			disasmOne(sink, vm.functions[vm.func].code[], ipCopy);
		}
		vmFormatError(vm, sink);
		sink("\n  ---\n");
	}

	private noreturn onCallFail() {
		sink("  ---\n");
		sink.formattedWrite("Test %s failed\n", test.name);
		printState();
		panic("Function expected to finish successfully");
	}

	// Takes exactly VmFunction.numStackParams arguments from the stack
	VmReg[] call(AllocId funcId, VmReg[] regParams...) {
		VmFunction* func = setupCall(funcId, 0, regParams);
		vm.run();
		// vm.runVerbose(sink);
		if (vm.status.isError) onCallFail();
		return vm.registers[0..func.numResults];
	}

	void callFail(AllocId funcId, VmReg[] regParams...) {
		setupCall(funcId, 0, regParams);
		vm.run();
		// vm.runVerbose(sink);
		if (!vm.status.isError) {
			panic("Function expected to trap");
		}
	}

	void expectStatus(VmStatus expected, string file = __FILE__, int line = __LINE__) {
		if (vm.status == expected) return;

		sink.formattedWrite("Unexpected VM status\n  Expected: %s\n", VmStatus_names[expected]);
		printState();
		panic(line, file, 1, "Unexpected VM status");
	}

	void expectResult(VmReg expected, string file = __FILE__, int line = __LINE__) {
		if (vm.status.isError) panic(line, file, 1, "Cannot check result on errorneous state %s", VmStatus_names[vm.status]);
		if (vm.registers[0] == expected) return;
		sink.formattedWrite("Test %s failed\n", test.name);
		sink.formattedWrite("Unexpected function result\n  Expected: %s\n       Got: %s\n", expected, vm.registers[0]);
		printState();
		panic(line, file, 1, "Unexpected function result");
	}

	AllocId memAlloc(MemoryKind kind, SizeAndAlign sizeAlign, MemoryFlags perm = MemoryFlags.read_write) {
		final switch(kind) with(MemoryKind) {
			case stack_mem: return vm.pushStackAlloc(sizeAlign, perm);
			case heap_mem, static_mem: return vm.memories[kind].allocate(*vm.allocator, sizeAlign, perm);
			case func_id: assert(false, "Cannot allocate function id");
		}
	}

	void memFree(AllocId id) {
		assert(id.kind == MemoryKind.heap_mem, "Can only free heap memory");
		Memory* mem = &vm.memories[id.kind];
		Allocation* alloc = &mem.allocations[id.index];
		alloc.markFreed;
	}

	AllocId memReadPtr(AllocId srcMem, u32 offset) {
		assert(srcMem.kind != MemoryKind.func_id, "Cannot read from function id");
		Memory* mem = &vm.memories[srcMem.kind];
		Allocation* alloc = &mem.allocations[srcMem.index];
		return memReadPtr(mem, alloc, offset);
	}

	AllocId memReadPtr(Memory* mem, Allocation* alloc, u32 offset) {
		return vm.pointerGet(mem, alloc, offset);
	}

	// Assumes that non-pointer data was already written
	void memWritePtr(AllocId dstMem, u32 offset, AllocId ptrVal) {
		assert(dstMem.kind != MemoryKind.func_id, "Cannot write to function id");
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

	SizeAndAlign memSizeAlign(AllocId id) {
		assert(id.kind != MemoryKind.func_id, "Cannot get size of function id");
		Memory* mem = &vm.memories[id.kind];
		Allocation* alloc = &mem.allocations[id.index];
		return alloc.sizeAlign;
	}

	static if (SANITIZE_UNINITIALIZED_MEM)
	void setAllocInitBitsRange(AllocId allocId, u32 start, u32 length, bool value) {
		Memory* mem = &vm.memories[allocId.kind];
		Allocation* alloc = &mem.allocations[allocId.index];
		mem.markInitBits(alloc.offset+start, length, value);
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
		return mem.countInitBits(alloc.offset, alloc.size);
	}
}
