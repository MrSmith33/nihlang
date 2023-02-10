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
	Array!VmFrame frames;
	Array!VmReg registers;

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
		frames.clear;
		registers.clear;
		foreach(ref mem; memories)
			mem.clear(*allocator, ptrSize);
		memories[MemoryKind.heap_mem].allocations.voidPut(*allocator, 1);
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

	AllocId addFunction(Array!u8 code, u8 numResults, u8 numParameters, u8 numLocalRegisters) {
		u32 index = functions.length;
		functions.put(*allocator, VmFunction(code, numResults, numParameters, numLocalRegisters));
		return AllocId(index, MemoryKind.func_id);
	}

	void pushRegisters(u32 numRegisters) {
		registers.voidPut(*allocator, numRegisters);
	}

	void pushRegisters(VmReg[] regs) {
		registers.put(*allocator, regs);
	}

	void pushRegister_u64(u64 val) {
		registers.put(*allocator, VmReg(val));
	}

	void pushRegister(VmReg val) {
		registers.put(*allocator, val);
	}

	VmReg getRegister(u32 index) {
		if(index >= registers.length) panic("Invalid register index (%s), only %s registers exist", index, registers.length);
		return registers[index];
	}

	// Assumes result and parameter registers to be setup
	void beginCall(AllocId funcId) {
		if(funcId.index >= functions.length) panic("Invalid function index (%s), only %s functions exist", funcId.index, functions.length);
		if(funcId.kind != MemoryKind.func_id) panic("Invalid AllocId kind, expected func_id, got %s", memoryKindString[funcId.kind]);
		VmFunction* func = &functions[funcId.index];
		VmFrame frame = {
			func : func,
			ip : 0,
		};
		frames.put(*allocator, frame);
		registers.voidPut(*allocator, func.numLocalRegisters);
	}

	void run() {
		isRunning = true;
		status = VmStatus.OK;

		while(isRunning) step();
	}

	void runVerbose(scope SinkDelegate sink) {
		isRunning = true;
		status = VmStatus.OK;

		sink("---");
		printRegs(sink);
		while(isRunning) {
			u32 ipCopy = frames.back.ip;
			disasmOne(sink, frames.back.func.code[], ipCopy);
			step();
			if (status != VmStatus.OK) {
				sink("Error: ");
				format_vm_error(sink);
				break;
			}
			printRegs(sink);
		}
		sink("---");
	}

	// Invariant: when trap happens, VM state should remain as if instruction was not executed
	void step() {
		if(frames.length == 0) panic("step: Frame stack is empty");
		VmFrame* frame = &frames.back();
		//enforce(frame.ip < frame.func.code.length, "IP is out of bounds (%s), code is %s bytes", frame.ip, frame.func.code.length);
		VmOpcode op = cast(VmOpcode)frame.func.code[frame.ip+0];

		final switch(op) with(VmOpcode) {
			case ret:
				registers.unput(frame.func.numParameters + frame.func.numLocalRegisters);
				frames.unput(1);

				if (frames.length == 0) {
					isRunning = false;
				}
				return;

			case trap:
				return setTrap(VmStatus.ERR_TRAP);

			case mov:
				u32 dstIndex = frame.firstRegister + frame.func.code[frame.ip+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				u32 srcIndex = frame.firstRegister + frame.func.code[frame.ip+2];
				if (srcIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, srcIndex);
				registers[dstIndex] = registers[srcIndex];
				frame.ip += 3;
				return;

			case add_i64:
				u32 dstIndex = frame.firstRegister + frame.func.code[frame.ip+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				VmReg* dst = &registers[dstIndex];
				u32 src0Index = frame.firstRegister + frame.func.code[frame.ip+2];
				if (src0Index >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, src0Index);
				VmReg* src0 = &registers[src0Index];
				u32 src1Index = frame.firstRegister + frame.func.code[frame.ip+3];
				if (src1Index >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, src1Index);
				VmReg* src1 = &registers[src1Index];
				dst.as_u64 = src0.as_u64 + src1.as_u64;
				dst.pointer = src0.pointer;
				if (src1.pointer.isDefined) return setTrap(VmStatus.ERR_PTR_SRC1);
				frame.ip += 4;
				return;

			case const_s8:
				u32 dstIndex = frame.firstRegister + frame.func.code[frame.ip+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				VmReg* dst = &registers[dstIndex];
				i8 imm = frame.func.code[frame.ip+2];
				dst.as_s64 = imm;
				dst.pointer = AllocId();
				frame.ip += 3;
				return;

			case load_m8:
			case load_m16:
			case load_m32:
			case load_m64:
				u32 size = 1 << (op - load_m8);

				u32 dstIndex = frame.firstRegister + frame.func.code[frame.ip+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				VmReg* dst = &registers[dstIndex];

				u32 srcIndex = frame.firstRegister + frame.func.code[frame.ip+2];
				if (srcIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, srcIndex);
				VmReg* src = &registers[srcIndex];

				if (src.pointer.isUndefined) return setTrap(VmStatus.ERR_LOAD_NOT_PTR);
				if (!isMemoryReadable(src.pointer.kind)) return setTrap(VmStatus.ERR_LOAD_NO_READ_PERMISSION);

				Memory* mem = &memories[src.pointer.kind];
				Allocation* alloc = &mem.allocations[src.pointer.index];
				u8* memory = mem.memory[].ptr;

				i64 offset = src.as_s64;
				if (offset < 0) return setTrap(VmStatus.ERR_LOAD_OOB);
				if (offset + size > alloc.size) return setTrap(VmStatus.ERR_LOAD_OOB);

				switch(op) {
					case load_m8:  dst.as_u64 = *cast( u8*)(memory + alloc.offset + offset); break;
					case load_m16: dst.as_u64 = *cast(u16*)(memory + alloc.offset + offset); break;
					case load_m32: dst.as_u64 = *cast(u32*)(memory + alloc.offset + offset); break;
					case load_m64: dst.as_u64 = *cast(u64*)(memory + alloc.offset + offset); break;
					default: assert(false);
				}

				// allocation size is never bigger than u32.max, so it is safe to cast valid offset to u32
				if (ptrSize.inBytes == size) {
					// this can be a pointer load
					dst.pointer = pointerGet(mem, alloc, cast(u32)offset);
				} else {
					dst.pointer = AllocId();
				}
				frame.ip += 3;
				return;

			case store_m8:
			case store_m16:
			case store_m32:
			case store_m64:
				u32 size = 1 << (op - store_m8);

				u32 dstIndex = frame.firstRegister + frame.func.code[frame.ip+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				VmReg* dst = &registers[dstIndex];

				u32 srcIndex = frame.firstRegister + frame.func.code[frame.ip+2];
				if (srcIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, srcIndex);
				VmReg* src = &registers[srcIndex];

				if (dst.pointer.isUndefined) return setTrap(VmStatus.ERR_STORE_NOT_PTR);
				if (!isMemoryWritable(dst.pointer.kind)) return setTrap(VmStatus.ERR_STORE_NO_WRITE_PERMISSION);

				Memory* mem = &memories[dst.pointer.kind];
				Allocation* alloc = &mem.allocations[dst.pointer.index];

				i64 offset = dst.as_s64;
				if (offset < 0) return setTrap(VmStatus.ERR_LOAD_OOB);
				if (offset + size > alloc.size) return setTrap(VmStatus.ERR_STORE_OOB);

				u8* memory = mem.memory[].ptr;
				switch(op) {
					case store_m8:  *cast( u8*)(memory+alloc.offset+offset) = src.as_u8; break;
					case store_m16: *cast(u16*)(memory+alloc.offset+offset) = src.as_u16; break;
					case store_m32: *cast(u32*)(memory+alloc.offset+offset) = src.as_u32; break;
					case store_m64: *cast(u64*)(memory+alloc.offset+offset) = src.as_u64; break;
					default: assert(false);
				}

				// allocation size is never bigger than u32.max, so it is safe to cast valid offset to u32
				if (ptrSize.inBytes == size) {
					// this can be a pointer store
					if (src.pointer.isDefined)
						pointerPut(mem, alloc, cast(u32)offset, src.pointer);
					else
						pointerRemove(mem, alloc, cast(u32)offset);
				}
				frame.ip += 3;
				return;
		}
	}

	private void setTrap(VmStatus status, u64 data = 0) {
		isRunning = false;
		this.status = status;
		this.errData = data;
	}

	AllocId pointerGet(Memory* mem, Allocation* alloc, u32 offset) {
		static if (MEMORY_RELOCATIONS_PER_ALLOCATION) {
			return alloc.relocations.get(offset);
		} else {
			return mem.relocations.get(cast(u32)(alloc.offset + offset));
		}
	}

	AllocId pointerPut(Memory* mem, Allocation* alloc, u32 offset, AllocId value) {
		AllocId oldPtr;
		static if (MEMORY_RELOCATIONS_PER_ALLOCATION) {
			alloc.relocations.put(*allocator, cast(u32)offset, value, oldPtr);
		} else {
			mem.relocations.put(*allocator, cast(u32)(alloc.offset + offset), value, oldPtr);
		}
		return oldPtr;
	}

	AllocId pointerRemove(Memory* mem, Allocation* alloc, u32 offset) {
		AllocId oldPtr;
		static if (MEMORY_RELOCATIONS_PER_ALLOCATION) {
			alloc.relocations.remove(*allocator, cast(u32)offset, oldPtr);
		} else {
			mem.relocations.remove(*allocator, cast(u32)(alloc.offset + offset), oldPtr);
		}
		return oldPtr;
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
		sink("     [");
		foreach(i, reg; registers) {
			if (i > 0) sink(", ");
			sink.formatValue(reg);
		}
		sink("]\n");
	}

	void format_vm_error(scope SinkDelegate sink) {
		if (status == VmStatus.OK) return;

		VmFrame* frame = &frames.back();
		u8[] code = frame.func.code[];
		u32 firstReg = frame.firstRegister;

		final switch(status) with(VmStatus) {
			case OK:
				sink("ok");
				break;

			case ERR_TRAP:
				sink("trap instruction reached.");
				break;

			case ERR_REGISTER_OOB:
				sink.formattedWrite("Trying to access register out of bounds of register stack.\n  Num frame registers: %s\n  Invalid register: r%s\n",
					registers.length - firstReg, errData - firstReg);
				break;

			case ERR_PTR_SRC1:
				VmReg* dst  = &registers[firstReg + code[frame.ip+1]];
				VmReg* src0 = &registers[firstReg + code[frame.ip+2]];
				VmReg* src1 = &registers[firstReg + code[frame.ip+3]];

				sink.formattedWrite("add.i64 can only contain pointers in the first argument.\n  r%s: %s\n  r%s: %s\n  r%s: %s\n",
					code[frame.ip+1], *dst,
					code[frame.ip+2], *src0,
					code[frame.ip+3], *src1);
				break;

			case ERR_STORE_NO_WRITE_PERMISSION:
				VmReg* dst = &registers[firstReg + code[frame.ip+1]];
				VmReg* src = &registers[firstReg + code[frame.ip+2]];

				sink.formattedWrite("Writing to %s pointer is disabled.\n  r%s: %s\n  r%s: %s\n",
					memoryKindString[dst.pointer.kind],
					code[frame.ip+1], *dst,
					code[frame.ip+2], *src);
				break;

			case ERR_LOAD_NO_READ_PERMISSION:
				VmReg* dst = &registers[firstReg + code[frame.ip+1]];
				VmReg* src = &registers[firstReg + code[frame.ip+2]];

				sink.formattedWrite("Reading from %s pointer is disabled.\n  r%s: %s\n  r%s: %s\n",
					memoryKindString[src.pointer.kind],
					code[frame.ip+1], *dst,
					code[frame.ip+2], *src);
				break;

			case ERR_STORE_NOT_PTR:
				VmReg* dst = &registers[firstReg + code[frame.ip+1]];

				sink.formattedWrite("Writing to non-pointer value (r%s:%s)", code[frame.ip+1], *dst);
				break;

			case ERR_LOAD_NOT_PTR:
				VmReg* src = &registers[firstReg + code[frame.ip+2]];

				sink.formattedWrite("Reading from non-pointer value (r%s:%s)", code[frame.ip+2], *src);
				break;

			case ERR_STORE_OOB:
				u8 op = code[frame.ip+0];
				u32 size = 1 << (op - VmOpcode.load_m8);
				VmReg* dst = &registers[firstReg + code[frame.ip+1]];
				Memory* mem = &memories[dst.pointer.kind];
				Allocation* alloc = &mem.allocations[dst.pointer.index];

				u64 offset = dst.as_u64;

				sink.formattedWrite("Writing past the end of the allocation (r%s:%s).\nWriting %s bytes at offset %s, to allocation of %s bytes\n",
					code[frame.ip+1], *dst,
					size,
					offset,
					alloc.size);
				break;

			case ERR_LOAD_OOB:
				u8 op = code[frame.ip+0];
				u32 size = 1 << (op - VmOpcode.load_m8);
				VmReg* src = &registers[firstReg + code[frame.ip+2]];
				Memory* mem = &memories[src.pointer.kind];
				Allocation* alloc = &mem.allocations[src.pointer.index];

				u64 offset = src.as_u64;

				sink.formattedWrite("Reading past the end of the allocation (r%s:%s).\nReading %s bytes at offset %s, from allocation of %s bytes\n",
					code[frame.ip+2], *src,
					size,
					offset,
					alloc.size);
				break;
		}
	}
}

enum VmStatus : u8 {
	OK,
	ERR_TRAP,
	ERR_REGISTER_OOB,
	ERR_PTR_SRC1,
	ERR_STORE_NO_WRITE_PERMISSION,
	ERR_LOAD_NO_READ_PERMISSION,
	ERR_STORE_NOT_PTR,
	ERR_LOAD_NOT_PTR,
	ERR_STORE_OOB,
	ERR_LOAD_OOB,
}

struct VmFunction {
	@nogc nothrow:

	Array!u8 code;
	u8 numResults;
	u8 numParameters;
	u8 numLocalRegisters;

	void free(ref VoxAllocator allocator) {
		code.free(allocator);
	}
}

struct VmFrame {
	@nogc nothrow:

	VmFunction* func;
	u32 ip;
	// index of the first register
	u32 firstRegister;
}
