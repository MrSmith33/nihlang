/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.state;

import vox.lib;
import vox.vm;

@nogc nothrow:


struct VmState {
	@nogc nothrow:

	// 4 or 8
	u8 ptrSize;
	u8 readWriteMask = MemFlags.heap_RW | MemFlags.stack_RW | MemFlags.static_R;

	bool isRunning = true;

	// must be checked on return
	VmStatus status;

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
		foreach(ref func; functions)
			func.free(*allocator);
		functions.clear;
		frames.clear;
		registers.clear;
		foreach(ref mem; memories)
			mem.clear(*allocator);
		memories[MemoryKind.heap_mem].allocations.voidPut(*allocator, 1);
	}

	bool isReadableMemory(MemoryKind kind) {
		return cast(bool)(readWriteMask & (1 << kind));
	}

	bool isWritableMemory(MemoryKind kind) {
		return cast(bool)(readWriteMask & (1 << (kind + 4)));
	}

	AllocId addFunction(Array!u8 code, u8 numResults, u8 numParameters, u8 numLocalRegisters) {
		u32 index = functions.length;
		functions.put(*allocator, VmFunction(code, numResults, numParameters, numLocalRegisters));
		u32 generation = 0;
		return AllocId(index, generation, MemoryKind.func_id);
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

		writeln("---");
		printRegs();
		while(isRunning) {
			u32 ipCopy = frames.back.ip;
			disasmOne(sink, frames.back.func.code[], ipCopy);
			step();
			if (status != VmStatus.OK) {
				sink("Error: ");
				format_vm_error(sink);
				break;
			}
			printRegs();
		}
		writeln("---");
	}

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
				u8 dst = frame.func.code[frame.ip+1];
				u8 src = frame.func.code[frame.ip+2];
				registers[frame.firstRegister + dst] = registers[frame.firstRegister + src];
				frame.ip += 3;
				return;

			case add_i64:
				VmReg* dst  = &registers[frame.firstRegister + frame.func.code[frame.ip+1]];
				VmReg* src0 = &registers[frame.firstRegister + frame.func.code[frame.ip+2]];
				VmReg* src1 = &registers[frame.firstRegister + frame.func.code[frame.ip+3]];
				dst.as_u64 = src0.as_u64 + src1.as_u64;
				dst.pointer = src0.pointer;
				if (src1.pointer.isDefined) return setTrap(VmStatus.ERR_PTR_SRC1);
				frame.ip += 4;
				return;

			case const_s8:
				VmReg* dst  = &registers[frame.firstRegister + frame.func.code[frame.ip+1]];
				i8 src = frame.func.code[frame.ip+2];
				dst.as_s64 = src;
				dst.pointer = AllocId();
				frame.ip += 3;
				return;

			case load_m8:
			case load_m16:
			case load_m32:
			case load_m64:
				u32 size = 1 << (op - load_m8);

				VmReg* dst = &registers[frame.firstRegister + frame.func.code[frame.ip+1]];
				VmReg* src = &registers[frame.firstRegister + frame.func.code[frame.ip+2]];

				if (src.pointer.isUndefined) return setTrap(VmStatus.ERR_LOAD_NOT_PTR);
				if (!isReadableMemory(src.pointer.kind)) return setTrap(VmStatus.ERR_LOAD_NO_READ_PERMISSION);

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
				if (ptrSize == size) {
					// this can be a pointer load
					static if (MEMORY_RELOCATIONS_PER_ALLOCATION) {
						dst.pointer = alloc.relocations.get(cast(u32)offset);
					} else {
						dst.pointer = mem.relocations.get(cast(u32)(alloc.offset + offset));
					}
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

				VmReg* dst  = &registers[frame.firstRegister + frame.func.code[frame.ip+1]];
				VmReg* src  = &registers[frame.firstRegister + frame.func.code[frame.ip+2]];

				if (dst.pointer.isUndefined) return setTrap(VmStatus.ERR_STORE_NOT_PTR);
				if (!isWritableMemory(dst.pointer.kind)) return setTrap(VmStatus.ERR_STORE_NO_WRITE_PERMISSION);

				Memory* mem = &memories[dst.pointer.kind];
				Allocation* alloc = &mem.allocations[dst.pointer.index];
				u8* memory = mem.memory[].ptr;

				i64 offset = dst.as_s64;
				if (offset < 0) return setTrap(VmStatus.ERR_LOAD_OOB);
				if (offset + size > alloc.size) return setTrap(VmStatus.ERR_STORE_OOB);

				switch(op) {
					case store_m8:  *cast( u8*)(memory+alloc.offset+offset) = src.as_u8; break;
					case store_m16: *cast(u16*)(memory+alloc.offset+offset) = src.as_u16; break;
					case store_m32: *cast(u32*)(memory+alloc.offset+offset) = src.as_u32; break;
					case store_m64: *cast(u64*)(memory+alloc.offset+offset) = src.as_u64; break;
					default: assert(false);
				}

				// allocation size is never bigger than u32.max, so it is safe to cast valid offset to u32
				if (ptrSize == size) {
					// this can be a pointer store
					static if (MEMORY_RELOCATIONS_PER_ALLOCATION) {
						if (src.pointer.isDefined)
							alloc.relocations.put(*allocator, cast(u32)offset, src.pointer);
						else
							alloc.relocations.remove(*allocator, cast(u32)offset);
					} else {
						if (src.pointer.isDefined)
							mem.relocations.put(*allocator, cast(u32)(alloc.offset + offset), src.pointer);
						else
							mem.relocations.remove(*allocator, cast(u32)(alloc.offset + offset));
					}
				}
				frame.ip += 3;
				return;
		}
	}

	private void setTrap(VmStatus status) {
		isRunning = false;
		this.status = status;
	}

	void printRegs() {
		write("     [");
		foreach(i, reg; registers) {
			if (i > 0) write(", ");
			write(reg);
		}
		writeln("]");
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
