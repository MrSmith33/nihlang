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
		memories[MemoryKind.static_mem].kind = MemoryKind.static_mem;
		memories[MemoryKind.heap_mem].kind   = MemoryKind.heap_mem;
		memories[MemoryKind.stack_mem].kind  = MemoryKind.stack_mem;

		memories[MemoryKind.static_mem].ptrSize = ptrSize;
		memories[MemoryKind.heap_mem].ptrSize   = ptrSize;
		memories[MemoryKind.stack_mem].ptrSize  = ptrSize;

		memories[MemoryKind.static_mem].reserve(*allocator, static_bytes);
		memories[MemoryKind.heap_mem].reserve(*allocator, heap_bytes);
		memories[MemoryKind.stack_mem].reserve(*allocator, stack_bytes);
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
			mem.clear(*allocator);
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

	void setAllocationPermission(AllocId id, MemoryFlags perm) {
		assert(id.kind != MemoryKind.func_id);
		Memory* mem = &memories[id.kind];
		assert(id.index < mem.allocations.length);
		Allocation* alloc = &mem.allocations[id.index];
		alloc.setPermission(perm);
	}

	bool isMemoryReadable(MemoryKind kind) {
		pragma(inline, true);
		return kind != MemoryKind.func_id;
	}

	bool isMemoryWritable(MemoryKind kind) {
		pragma(inline, true);
		return kind != MemoryKind.func_id;
	}

	bool isMemoryRefcounted(MemoryKind kind) {
		pragma(inline, true);
		return kind != MemoryKind.func_id;
	}

	AllocId addFunction() {
		u32 index = functions.length;
		functions.put(*allocator, VmFunction());
		return AllocId(index, MemoryKind.func_id);
	}

	AllocId addFunction(
		NumResults numResults,
		NumRegParams numRegParams,
		NumStackParams numStackParams,
		Array!u8 code)
	{
		u32 index = functions.length;
		functions.put(*allocator, VmFunction());
		auto id = AllocId(index, MemoryKind.func_id);
		auto builder = CodeBuilder(allocator, code);
		setFunction(id, numResults, numRegParams, numStackParams, builder);
		return id;
	}

	AllocId addFunction(
		NumResults numResults,
		NumRegParams numRegParams,
		NumStackParams numStackParams,
		ref CodeBuilder builder)
	{
		u32 index = functions.length;
		functions.put(*allocator, VmFunction());
		auto id = AllocId(index, MemoryKind.func_id);
		setFunction(id, numResults, numRegParams, numStackParams, builder);
		return id;
	}

	void setFunction(
		AllocId id,
		NumResults numResults,
		NumRegParams numRegParams,
		NumStackParams numStackParams,
		ref CodeBuilder builder)
	{
		assert(id.index < functions.length);
		if (numStackParams.val > builder.stack.length) {
			panic("Ivalid function properties: Number of stack parameters (%s) is bigger than stack slot size (%s)",
			numStackParams.val, builder.stack.length);
		}
		functions[id.index] = VmFunction(VmFuncKind.bytecode, numResults.val, numRegParams.val, numStackParams.val, builder.stack, builder.code);
	}

	AllocId addExternalFunction(
		NumResults numResults,
		NumRegParams numRegParams,
		VmExternalFn fn,
		void* userData = null)
	{
		return addExternalFunction(
			numResults,
			numRegParams,
			0.NumStackParams,
			Array!SizeAndAlign.init,
			fn,
			userData);
	}

	AllocId addExternalFunction(
		NumResults numResults,
		NumRegParams numRegParams,
		NumStackParams numStackParams,
		Array!SizeAndAlign stack,
		VmExternalFn fn,
		void* userData = null)
	{
		u32 index = functions.length;
		if (numStackParams.val > stack.length) {
			panic("Ivalid function properties: Number of stack parameters (%s) is bigger than stack slot size (%s)",
			numStackParams.val, stack.length);
		}
		VmFunction f = {
			kind : VmFuncKind.external,
			numResults : numResults.val,
			numRegParams : numRegParams.val,
			numStackParams : numStackParams.val,
			stackSlotSizes : stack,
			external : fn,
			externalUserData : userData,
		};
		functions.put(*allocator, f);
		return AllocId(index, MemoryKind.func_id);
	}

	AllocId pushStackAlloc(SizeAndAlign sizeAlign, MemoryFlags perm = MemoryFlags.read_write) {
		assert(numFrameStackSlots < u8.max);
		return memories[MemoryKind.stack_mem].allocate(*allocator, sizeAlign, perm);
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
		static if (FAST_CHECKS) if (offset % ptrSize.inBytes != 0) panic("Unaligned offset");
		static if (OUT_REFS_PER_ALLOCATION) {
			return alloc.outRefs.get(offset);
		} else {
			if (alloc.numOutRefs == 0) return AllocId.init;
			AllocId res = mem.outRefs.get(cast(u32)(alloc.offset + offset));
			static if (FAST_CHECKS) {
				PointerId slot = memOffsetToPtrIndex(alloc.offset + offset, ptrSize);
				usz* ptrBits = cast(usz*)&mem.pointerBitmap.front();
				if (mem.getPtrBit(slot) != res.isDefined) {
					AllocId allocId = AllocId(cast(u32)(alloc - &mem.allocations.front()), mem.kind);
					panic("Invariant failed: in allocation %s mem.outRefs contains pointer (%s) at offset %s, while pointer bit is not set. Bitmap addr: %s\n",
						allocId,
						res,
						offset, ptrBits);
				}
			}
			return res;
		}
	}

	AllocId pointerPut(Memory* mem, Allocation* alloc, u32 offset, AllocId value) {
		assert(value.isDefined);
		static if (FAST_CHECKS) if (offset % ptrSize.inBytes != 0) panic("Unaligned offset");
		AllocId oldPtr;
		static if (OUT_REFS_PER_ALLOCATION) {
			alloc.outRefs.put(*allocator, cast(u32)offset, value, oldPtr);
		} else {
			mem.outRefs.put(*allocator, cast(u32)(alloc.offset + offset), value, oldPtr);
		}
		if (oldPtr.isDefined) {
			changeAllocInRef(oldPtr, -1);
		} else {
			static if (OUT_REFS_PER_MEMORY) {
				++alloc.numOutRefs;
			}
			PointerId ptrSlotIndex = memOffsetToPtrIndex(alloc.offset + offset, ptrSize);
			mem.setPtrBit(ptrSlotIndex);
		}
		changeAllocInRef(value, 1);
		return oldPtr;
	}

	AllocId pointerRemove(Memory* mem, Allocation* alloc, u32 offset) {
		static if (FAST_CHECKS) if (offset % ptrSize.inBytes != 0) panic("Unaligned offset");
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
			PointerId ptrSlotIndex = memOffsetToPtrIndex(alloc.offset + offset, ptrSize);
			mem.resetPtrBit(ptrSlotIndex);
			changeAllocInRef(oldPtr, -1);
		}
		return oldPtr;
	}

	// delta should be -1 or 1
	void changeAllocInRef(AllocId allocId, int delta) {
		assert(delta == 1 || delta == -1);
		if (!isMemoryRefcounted(allocId.kind)) return;
		Memory* mem = &memories[allocId.kind];
		Allocation* alloc = &mem.allocations[allocId.index];
		alloc.numInRefs += delta;
		assert(alloc.numInRefs != typeof(alloc.numInRefs).max);
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
		sink.formattedWrite("Allocation %s, %X..%X, %s bytes\n", allocId, offset, offset+length, length);

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
			auto end = min(index + bytesPerLine, bytes.length);
			printBytes(bytes[index .. end]);
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
