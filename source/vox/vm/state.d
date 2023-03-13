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

	bool isRunning = true;

	// must be checked on return
	VmStatus status;
	u64 errData;

	VoxAllocator* allocator;
	Memory[3] memories;

	Array!VmFunction functions;
	Array!VmFrame callerFrames; // current function doesn't have a frame
	Array!VmReg registers;

	u32 numCalls;

	FuncId func;
	u32 ip;
	u8* code;
	VmReg* regs;
	u32 frameFirstReg() const {
		return cast(u32)(regs - &registers[0]);
	}

	void reserveMemory(u32 static_bytes, u32 heap_bytes, u32 stack_bytes) {
		memories[MemoryKind.static_mem].reserve(*allocator, static_bytes, ptrSize);
		memories[MemoryKind.heap_mem].reserve(*allocator, heap_bytes, ptrSize);
		memories[MemoryKind.stack_mem].reserve(*allocator, stack_bytes, ptrSize);
		// skip one allocation for null pointer
		memories[MemoryKind.heap_mem].allocations.voidPut(*allocator, 1);
	}

	void reset() {
		errData = 0;
		foreach(ref func; functions)
			func.free(*allocator);
		functions.clear;
		callerFrames.clear;
		registers.clear;
		foreach(ref mem; memories)
			mem.clear(*allocator, ptrSize);
		memories[MemoryKind.heap_mem].allocations.voidPut(*allocator, 1);

		numCalls = 0;
		func = 0;
		ip = 0;
		code = null;

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

	AllocId addFunction(u8 numResults, u8 numParameters, Array!u8 code) {
		u32 index = functions.length;
		functions.put(*allocator, VmFunction(VmFuncKind.bytecode, numResults, numParameters, code));
		return AllocId(index, MemoryKind.func_id);
	}

	AllocId addExternalFunction(u8 numResults, u8 numParameters, VmExternalFn fn, void* userData = null) {
		u32 index = functions.length;
		VmFunction f = {
			kind : VmFuncKind.external,
			numResults : numResults,
			numParameters : numParameters,
			external : fn,
			externalUserData : userData,
		};
		functions.put(*allocator, f);
		return AllocId(index, MemoryKind.func_id);
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
		isRunning = true;
		status = VmStatus.OK;

		while(isRunning) vmStep(this);
	}

	void runVerbose(scope SinkDelegate sink) {
		isRunning = true;
		status = VmStatus.OK;

		sink("---\n");
		printRegs(sink);
		while(isRunning) {
			u32 ipCopy = ip;
			disasmOne(sink, functions[func].code[], ipCopy);
			vmStep(this);
			if (status != VmStatus.OK) {
				sink("Error: ");
				vmFormatError(this, sink);
				sink("\n");
				break;
			}
			printRegs(sink);
			// writefln("stack: %s", frames.length+1);
		}
		sink("---\n");
	}

	void setTrap(VmStatus status, u64 data = 0) {
		isRunning = false;
		this.status = status;
		this.errData = data;
	}

	AllocId pointerGet(Memory* mem, Allocation* alloc, u32 offset) {
		static if (CONSISTENCY_CHECKS) if (offset % ptrSize.inBytes != 0) panic("Unaligned offset");
		static if (MEMORY_RELOCATIONS_PER_ALLOCATION) {
			return alloc.relocations.get(offset);
		} else {
			return mem.relocations.get(cast(u32)(alloc.offset + offset));
		}
	}

	AllocId pointerPut(Memory* mem, Allocation* alloc, u32 offset, AllocId value) {
		static if (CONSISTENCY_CHECKS) if (offset % ptrSize.inBytes != 0) panic("Unaligned offset");
		AllocId oldPtr;
		static if (MEMORY_RELOCATIONS_PER_ALLOCATION) {
			alloc.relocations.put(*allocator, cast(u32)offset, value, oldPtr);
		} else {
			mem.relocations.put(*allocator, cast(u32)(alloc.offset + offset), value, oldPtr);
		}
		return oldPtr;
	}

	AllocId pointerRemove(Memory* mem, Allocation* alloc, u32 offset) {
		static if (CONSISTENCY_CHECKS) if (offset % ptrSize.inBytes != 0) panic("Unaligned offset");
		AllocId oldPtr;
		static if (MEMORY_RELOCATIONS_PER_ALLOCATION) {
			alloc.relocations.remove(*allocator, cast(u32)offset, oldPtr);
		} else {
			mem.relocations.remove(*allocator, cast(u32)(alloc.offset + offset), oldPtr);
		}
		return oldPtr;
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
		size_t* initBits = cast(size_t*)&mem.initBitmap.front();

		size_t index = 0;

		if (bytesPerLine) {
			while (index + bytesPerLine <= bytes.length) {
				printIndent(sink, indentation);
				foreach(i, b; bytes[index..index+bytesPerLine]) {
					if (getBitAt(initBits, index+i))
						sink.formattedWrite("%02X ", b);
					else
						sink("?? ");
				}
				sink("\n");
				index += bytesPerLine;
			}
		}

		if (index < bytes.length) {
			printIndent(sink, indentation);
			foreach(i, b; bytes[index..$]) {
				if (getBitAt(initBits, index+i))
					sink.formattedWrite("%02X ", b);
				else
					sink("?? ");
			}
			sink("\n");
		}
	}
}

struct VmFunction {
	@nogc nothrow:

	VmFuncKind kind;
	u8 numResults;
	u8 numParameters;

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
	}
}

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
	u32 regOffset;
}

struct FuncId {
	@nogc nothrow:
	u32 index;
	alias index this;
}
