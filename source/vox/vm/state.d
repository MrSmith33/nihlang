/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.state;

import vox.lib;
import vox.vm;

@nogc nothrow:


struct VmState {
	@nogc nothrow:

	PtrSize ptrSize;
	u8 readWriteMask = MemFlags.heap_RW | MemFlags.stack_RW | MemFlags.static_R;

	// must be checked on return
	VmStatus status = VmStatus.RUNNING;
	u64 errData;
	u64 budget = u64.max;

	VoxAllocator* allocator;
	Memory[3] memories;

	Array!VmFunction functions;
	Array!VmFrame callerFrames; // current function doesn't have a frame
	Array!VmReg registers;

	u32 numCalls;

	// stack frame data
	FuncId func;
	u32 ip;
	u8* code;
	VmReg* regs;
	Allocation* stackSlots() {
		pragma(inline, true);
		return &memories[MemoryKind.stack_mem].allocations[frameFirstStackSlot];
	}
	u32 frameFirstReg() const {
		pragma(inline, true);
		return cast(u32)(regs - &registers[0]);
	}
	u32 frameFirstStackSlot;
	u8 numFrameStackSlots() const {
		pragma(inline, true);
		return cast(u8)(memories[MemoryKind.stack_mem].allocations.length - frameFirstStackSlot);
	}

	void reserveMemory(u32 static_bytes, u32 heap_bytes, u32 stack_bytes) {
		memories[MemoryKind.static_mem].reserve(*allocator, static_bytes, ptrSize);
		memories[MemoryKind.heap_mem].reserve(*allocator, heap_bytes, ptrSize);
		memories[MemoryKind.stack_mem].reserve(*allocator, stack_bytes, ptrSize);
		// skip one allocation for null pointer
		memories[MemoryKind.heap_mem].allocations.voidPut(*allocator, 1);
	}

	void reset() {
		status = VmStatus.RUNNING;
		errData = 0;
		foreach(ref func; functions)
			func.free(*allocator);
		functions.clear;
		callerFrames.clear;
		registers.clear;
		foreach(ref mem; memories) {
			mem.clear(*allocator, ptrSize);
		}
		// null allocation
		memories[MemoryKind.heap_mem].allocations.put(*allocator, Allocation());
		// native caller function
		VmFunction f = {
			kind : VmFuncKind.external,
		};
		functions.put(*allocator, f);

		budget = u64.max;
		numCalls = 0;
		func = FuncId(0); // native caller function
		ip = 0;
		code = null;
		frameFirstStackSlot = 0;

		// Each function can access top 256 registers
		pushRegisters(256);
		regs = &registers[0];
	}

	bool isMemoryReadable(MemoryKind kind) {
		return cast(bool)(readWriteMask & (1 << kind));
	}

	bool isMemoryWritable(MemoryKind kind) {
		return cast(bool)(readWriteMask & (1 << (kind + 4)));
	}

	bool isMemoryRefcounted(MemoryKind kind) {
		return kind < MemoryKind.func_id;
	}

	AllocId addFunction(
		NumResults numResults,
		NumRegParams numRegParams,
		NumStackParams numStackParams,
		Array!u8 code)
	{
		u32 index = functions.length;
		functions.put(*allocator, VmFunction(VmFuncKind.bytecode, numResults.val, numRegParams.val, numStackParams.val, Array!SizeAndAlign.init, code));
		return AllocId(index, MemoryKind.func_id);
	}

	AllocId addFunction(
		NumResults numResults,
		NumRegParams numRegParams,
		NumStackParams numStackParams,
		ref CodeBuilder builder)
	{
		u32 index = functions.length;
		functions.put(*allocator, VmFunction(VmFuncKind.bytecode, numResults.val, numRegParams.val, numStackParams.val, builder.stack, builder.code));
		return AllocId(index, MemoryKind.func_id);
	}

	AllocId addExternalFunction(
		NumResults numResults,
		NumRegParams numRegParams,
		NumStackParams numStackParams,
		VmExternalFn fn,
		void* userData = null)
	{
		u32 index = functions.length;
		VmFunction f = {
			kind : VmFuncKind.external,
			numResults : numResults.val,
			numRegParams : numRegParams.val,
			numStackParams : numStackParams.val,
			external : fn,
			externalUserData : userData,
		};
		functions.put(*allocator, f);
		return AllocId(index, MemoryKind.func_id);
	}

	AllocId pushStackAlloc(SizeAndAlign sizeAlign) {
		assert(numFrameStackSlots < u8.max);
		return memories[MemoryKind.stack_mem].allocate(*allocator, sizeAlign, MemoryKind.stack_mem);
	}

	void pushRegisters(u32 numRegisters) {
		auto regs = registers.voidPut(*allocator, numRegisters);
		static if (INIT_REGISTERS) {
			regs[] = VmReg.init;
		}
	}

	void popRegisters(u32 numRegisters) {
		registers.unput(numRegisters);
	}

	VmReg getRegister(u32 index) {
		if(index >= registers.length) panic("Invalid register index (%s), only %s registers exist", index, registers.length);
		return registers[index];
	}

	// Assumes parameter registers to be setup
	void beginCall(AllocId funcId) {
		if(funcId.index >= functions.length) panic("Invalid function index (%s), only %s functions exist", funcId.index, functions.length);
		if(funcId.kind != MemoryKind.func_id) panic("Invalid AllocId kind, expected func_id, got %s", memoryKindString[funcId.kind]);
		func = FuncId(funcId.index);
		regs = &registers[0];
		code = functions[func].code[].ptr;
	}

	void run() {
		while (status == VmStatus.RUNNING) {
			if (budget == 0) {
				status = VmStatus.ERR_BUDGET;
				return;
			}
			vmStep(this);
			--budget;
		}
	}

	void runVerbose(scope SinkDelegate sink) {
		sink("---\n");
		// printRegs(sink);
		scope(exit) sink("---\n");
		while (status == VmStatus.RUNNING) {
			if (budget == 0) {
				status = VmStatus.ERR_BUDGET;
				return;
			}
			u32 ipCopy = ip;
			disasmOne(sink, functions[func].code[], ipCopy);
			sink("\n");
			vmStep(this);
			if (status.isError) {
				sink("Error: ");
				vmFormatError(this, sink);
				sink("\n");
			}
			//printRegs(sink);
			// writefln("stack: %s", frames.length+1);
			--budget;
		}
	}

	void setTrap(VmStatus status, u64 data = 0) {
		this.status = status;
		this.errData = data;
	}

	AllocId pointerGet(Memory* mem, Allocation* alloc, u32 offset) {
		static if (CONSISTENCY_CHECKS) if (offset % ptrSize.inBytes != 0) panic("Unaligned offset");
		static if (OUT_REFS_PER_ALLOCATION) {
			return alloc.outRefs.get(offset);
		} else {
			if (alloc.numOutRefs == 0) return AllocId.init;
			return mem.outRefs.get(cast(u32)(alloc.offset + offset));
		}
	}

	AllocId pointerPut(Memory* mem, Allocation* alloc, u32 offset, AllocId value) {
		assert(value.isDefined);
		static if (CONSISTENCY_CHECKS) if (offset % ptrSize.inBytes != 0) panic("Unaligned offset");
		AllocId oldPtr;
		static if (OUT_REFS_PER_ALLOCATION) {
			alloc.outRefs.put(*allocator, cast(u32)offset, value, oldPtr);
		} else {
			mem.outRefs.put(*allocator, cast(u32)(alloc.offset + offset), value, oldPtr);
		}
		if (oldPtr.isDefined) {
			decAllocInRef(oldPtr);
		} else {
			static if (OUT_REFS_PER_MEMORY) {
				++alloc.numOutRefs;
			}
			u32 ptrSlotIndex = memOffsetToPtrIndex(alloc.offset + offset, ptrSize);
			mem.setPtrBit(ptrSlotIndex);
		}
		incAllocInRef(value);
		return oldPtr;
	}

	AllocId pointerRemove(Memory* mem, Allocation* alloc, u32 offset) {
		static if (CONSISTENCY_CHECKS) if (offset % ptrSize.inBytes != 0) panic("Unaligned offset");
		AllocId oldPtr;
		static if (OUT_REFS_PER_ALLOCATION) {
			alloc.outRefs.remove(*allocator, cast(u32)offset, oldPtr);
		} else {
			mem.outRefs.remove(*allocator, cast(u32)(alloc.offset + offset), oldPtr);
		}
		if (oldPtr.isDefined) {
			static if (OUT_REFS_PER_MEMORY) {
				--alloc.numOutRefs;
			}
			u32 ptrSlotIndex = memOffsetToPtrIndex(alloc.offset + offset, ptrSize);
			mem.resetPtrBit(ptrSlotIndex);
			decAllocInRef(oldPtr);
		}
		return oldPtr;
	}

	void incAllocInRef(AllocId allocId) {
		if (!isMemoryRefcounted(allocId.kind)) return;
		Memory* mem = &memories[allocId.kind];
		Allocation* alloc = &mem.allocations[allocId.index];
		++alloc.numInRefs;
	}

	void decAllocInRef(AllocId allocId) {
		if (!isMemoryRefcounted(allocId.kind)) return;
		Memory* mem = &memories[allocId.kind];
		Allocation* alloc = &mem.allocations[allocId.index];
		assert(alloc.numInRefs > 0);
		--alloc.numInRefs;
	}

	bool isPointerValid(AllocId ptr) {
		// Pointer validity check should go here
		// TODO: Relevant tests must be added when this is implemented
		return true;
	}

	// For VM users
	void memWrite(T)(AllocId dstMem, u32 offset, T value)
		if(is(T == u8) || is(T == u16) || is(T == u32) || is(T == u64))
	{
		Memory* mem = &memories[dstMem.kind];
		Allocation* alloc = &mem.allocations[dstMem.index];
		u8* memory = mem.memory[].ptr;
		*cast(T*)(memory + alloc.offset + offset) = value;
	}

	static if (SANITIZE_UNINITIALIZED_MEM)
	void markInitialized(AllocId dstMem, u32 offset, u32 size) {
		Memory* mem = &memories[dstMem.kind];
		Allocation* alloc = &mem.allocations[dstMem.index];
		mem.markInitBits(alloc.offset + offset, size, true);
	}

	// For VM users
	T memRead(T)(Memory* mem, Allocation* alloc, u32 offset)
		if(is(T == u8) || is(T == u16) || is(T == u32) || is(T == u64))
	{
		u8* memory = mem.memory[].ptr;
		return *cast(T*)(memory + alloc.offset + offset);
	}

	// no OOB check
	u64 memReadPtrSize(Memory* mem, Allocation* alloc, u32 offset) {
		final switch(ptrSize) {
			case PtrSize._32: return memRead!u32(mem, alloc, offset);
			case PtrSize._64: return memRead!u64(mem, alloc, offset);
		}
	}

	void printRegs(scope SinkDelegate sink) {
		u32 numTotalRegs = registers.length;

		sink("     [");
		foreach(i, reg; regs[0..256]) {
			if (i > 0) {
				if (i == numTotalRegs) sink("; ");
				else sink(", ");
			}
			sink.formatValue(reg);
		}
		sink("]\n");
	}

	void printMem(scope SinkDelegate sink, AllocId allocId, u32 offset, u32 length, u32 bytesPerLine = 16, u32 indentation = 0) {
		static immutable char[16] spaces = ' ';

		static void printIndent(scope SinkDelegate sink, u32 indentation) {
			while(indentation > spaces.length) {
				sink(spaces);
				indentation -= spaces.length;
			}
			if (indentation) sink(spaces[0..indentation]);
		}

		printIndent(sink, indentation);
		sink.formattedWrite("Memory %s, %X..%X, %s bytes\n", allocId, offset, offset+length, length);

		Memory* mem = &memories[allocId.kind];
		Allocation* alloc = &mem.allocations[allocId.index];
		u8[] bytes = mem.memory[offset..offset+length];

		static if (SANITIZE_UNINITIALIZED_MEM) {
			size_t* initBits = cast(size_t*)&mem.initBitmap.front();
		}

		size_t index = 0;

		void printBytes(u8[] bytes) {
			foreach(i, b; bytes) {
				static if (SANITIZE_UNINITIALIZED_MEM) {
					if (getBitAt(initBits, index+i))
						sink.formattedWrite("%02X ", b);
					else
						sink("?? ");
				} else {
					sink.formattedWrite("%02X ", b);
				}
			}
		}

		if (bytesPerLine) {
			while (index + bytesPerLine <= bytes.length) {
				printIndent(sink, indentation);
				printBytes(bytes[index..index+bytesPerLine]);
				sink("\n");
				index += bytesPerLine;
			}
		}

		if (index < bytes.length) {
			printIndent(sink, indentation);
			printBytes(bytes[index..index+bytesPerLine]);
			sink("\n");
		}
	}
}

struct VmFunction {
	@nogc nothrow:

	VmFuncKind kind;
	u8 numResults;
	u8 numRegParams;
	u8 numStackParams;
	Array!SizeAndAlign stackSlotSizes;

	union {
		Array!u8 code;
		struct {
			VmExternalFn external;
			void* externalUserData;
		}
	}

	void free(ref VoxAllocator allocator) {
		final switch (kind) {
			case VmFuncKind.bytecode:
				code.free(allocator);
				break;
			case VmFuncKind.external: break;
		}
		stackSlotSizes.free(allocator);
	}
}

struct NumResults { u8 val; }
struct NumRegParams { u8 val; }
struct NumStackParams { u8 val; }

enum VmFuncKind : u8 {
	bytecode,
	external,
}

alias VmExternalFn = extern(C) void function(ref VmState state, void* userData);

struct VmFrame {
	@nogc nothrow:

	FuncId func;
	u32 ip;
	// Number of registers pushed during call
	u8 regDelta;
	// Number of stack parameters in the frame (stackSlotSizes.length)
	u8 numStackSlots;
}

struct FuncId {
	@nogc nothrow:
	u32 index;
	alias index this;
}
