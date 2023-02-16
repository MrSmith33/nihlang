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

	u32 frameFuncIndex;
	u32 frameFirstReg;
	u32 frameIp;
	u8* frameCode;

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
		frameFuncIndex = 0;
		frameFirstReg = 0;
		frameIp = 0;
		frameCode = null;
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

	AllocId addFunction(u8 numResults, u8 numParameters, u8 numLocals, Array!u8 code) {
		u32 index = functions.length;
		functions.put(*allocator, VmFunction(VmFuncKind.bytecode, numResults, numParameters, numLocals, code));
		return AllocId(index, MemoryKind.func_id);
	}

	AllocId addExternalFunction(u8 numResults, u8 numParameters, u8 numLocals, VmExternalFn fn, void* userData = null) {
		u32 index = functions.length;
		VmFunction f = {
			kind : VmFuncKind.external,
			numResults : numResults,
			numParameters : numParameters,
			numLocals : numLocals,
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
		pushRegisters(func.numLocals);

		frameFuncIndex = funcId.index;
		frameFirstReg = 0;
		frameIp = 0;
		frameCode = func.code[].ptr;
	}

	void run() {
		isRunning = true;
		status = VmStatus.OK;

		while(isRunning) step();
	}

	void runVerbose(scope SinkDelegate sink) {
		isRunning = true;
		status = VmStatus.OK;

		sink("---\n");
		printRegs(sink);
		while(isRunning) {
			u32 ipCopy = frameIp;
			disasmOne(sink, functions[frameFuncIndex].code[], ipCopy);
			step();
			if (status != VmStatus.OK) {
				sink("Error: ");
				format_vm_error(sink);
				sink("\n");
				break;
			}
			printRegs(sink);
			// writefln("stack: %s", frames.length+1);
		}
		sink("---\n");
	}

	// Invariant: when trap happens, VM state should remain as if instruction was not executed
	void step() {
		VmOpcode op = cast(VmOpcode)frameCode[frameIp+0];

		final switch(op) with(VmOpcode) {
			case ret:
				VmFunction* func = &functions[frameFuncIndex];
				registers.unput(func.numParameters + func.numLocals);

				if (callerFrames.length == 0) {
					isRunning = false;
					frameFirstReg = 0;
					frameFuncIndex = 0;
					frameIp = 0;
					frameCode = null;
				} else {
					VmFrame* frame = &callerFrames.back();
					frameFirstReg = frame.firstRegister;
					frameFuncIndex = frame.funcIndex;
					frameIp = frame.ip;
					frameCode = functions[frameFuncIndex].code[].ptr;
					callerFrames.unput(1);
				}
				//++numCalls;
				return;

			case trap:
				return setTrap(VmStatus.ERR_TRAP);

			case jump:
				i32 offset = *cast(i32*)&frameCode[frameIp+1];
				frameIp += offset + 5;
				return;

			case branch:
				u32 srcIndex = frameFirstReg + frameCode[frameIp+1];
				if (srcIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, srcIndex);
				VmReg* src = &registers[srcIndex];

				i32 offset = *cast(i32*)&frameCode[frameIp+2];

				if (src.as_u64 || src.pointer.isDefined) {
					frameIp += offset + 6;
					return;
				}

				frameIp += 6;
				return;

			case push:
				u8 length = frameCode[frameIp+1];
				pushRegisters(length);
				frameIp += 2;
				return;

			case pop:
				u8 length = frameCode[frameIp+1];
				popRegisters(length);
				frameIp += 2;
				return;

			case call:
				u32 funcIndex = *cast(i32*)&frameCode[frameIp+1];

				if(funcIndex >= functions.length) panic("Invalid function index (%s), only %s functions exist", funcIndex, functions.length);

				VmFunction* callee = &functions[funcIndex];

				VmFunction* caller = &functions[frameFuncIndex];
				u32 calleeFirstRegister = frameFirstReg + caller.numResults + caller.numParameters + caller.numLocals;

				if(calleeFirstRegister + callee.numResults + callee.numParameters != registers.length)
					panic("Invalid stack setup");

				// modify current frame here, before pushing new one, as reallocation might happen
				frameIp += 5;

				if (callee.kind == VmFuncKind.external && callee.external == null) panic("VmFunction.external is not set");

				VmFrame callerFrame = {
					funcIndex : frameFuncIndex,
					ip : frameIp,
					firstRegister : frameFirstReg,
				};
				callerFrames.put(*allocator, callerFrame);

				frameFirstReg = calleeFirstRegister;
				frameFuncIndex = funcIndex;
				frameIp = 0;

				final switch(callee.kind) {
					case VmFuncKind.bytecode:
						frameCode = callee.code[].ptr;
						pushRegisters(callee.numLocals);
						return;

					case VmFuncKind.external:
						frameCode = null;
						// call
						callee.external(this, callee.externalUserData);
						// restore
						registers.unput(callee.numParameters + callee.numLocals);
						VmFrame* frame = &callerFrames.back();
						frameFirstReg = frame.firstRegister;
						frameFuncIndex = frame.funcIndex;
						frameIp = frame.ip;
						frameCode = caller.code[].ptr;
						callerFrames.unput(1);
						return;
				}

			case mov:
				u32 dstIndex = frameFirstReg + frameCode[frameIp+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				u32 srcIndex = frameFirstReg + frameCode[frameIp+2];
				if (srcIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, srcIndex);
				registers[dstIndex] = registers[srcIndex];
				frameIp += 3;
				return;

			// u8 op, VmBinCond cmp_op, u8 dst, u8 src0, u8 src1
			case cmp:
				VmBinCond cond = cast(VmBinCond)frameCode[frameIp+1];
				if (cond > VmBinCond.max) return setTrap(VmStatus.ERR_COND_OOB, cond);

				u32 dstIndex = frameFirstReg + frameCode[frameIp+2];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				VmReg* dst = &registers[dstIndex];

				u32 src0Index = frameFirstReg + frameCode[frameIp+3];
				if (src0Index >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, src0Index);
				VmReg* src0 = &registers[src0Index];

				u32 src1Index = frameFirstReg + frameCode[frameIp+4];
				if (src1Index >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, src1Index);
				VmReg* src1 = &registers[src1Index];

				final switch(cond) with(VmBinCond) {
					case m64_eq:
						dst.as_u64 = src0.as_u64 == src1.as_u64 && src0.pointer == src1.pointer;
						break;
					case m64_ne:
						dst.as_u64 = src0.as_u64 != src1.as_u64 || src0.pointer != src1.pointer;
						break;
					case u64_gt:
						if (src0.pointer != src1.pointer) return setTrap(VmStatus.ERR_CMP_DIFFERENT_PTR);
						dst.as_u64 = src0.as_u64 >  src1.as_u64;
						break;
					case u64_ge:
						if (src0.pointer != src1.pointer) return setTrap(VmStatus.ERR_CMP_DIFFERENT_PTR);
						dst.as_u64 = src0.as_u64 >= src1.as_u64;
						break;
					case s64_gt:
						if (src0.pointer.isDefined || src1.pointer.isDefined) return setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
						dst.as_u64 = src0.as_s64 >  src1.as_s64;
						break;
					case s64_ge:
						if (src0.pointer.isDefined || src1.pointer.isDefined) return setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
						dst.as_u64 = src0.as_s64 >= src1.as_s64;
						break;

					case f32_gt:
						if (src0.pointer.isDefined || src1.pointer.isDefined) return setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
						dst.as_u64 = src0.as_f32 >  src1.as_f32;
						break;
					case f32_ge:
						if (src0.pointer.isDefined || src1.pointer.isDefined) return setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
						dst.as_u64 = src0.as_f32 >= src1.as_f32;
						break;
					case f64_gt:
						if (src0.pointer.isDefined || src1.pointer.isDefined) return setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
						dst.as_u64 = src0.as_f64 >  src1.as_f64;
						break;
					case f64_ge:
						if (src0.pointer.isDefined || src1.pointer.isDefined) return setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
						dst.as_u64 = src0.as_f64 >= src1.as_f64;
						break;
				}

				dst.pointer = AllocId();
				frameIp += 5;
				break;

			case add_i64:
				u32 dstIndex = frameFirstReg + frameCode[frameIp+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				VmReg* dst = &registers[dstIndex];
				u32 src0Index = frameFirstReg + frameCode[frameIp+2];
				if (src0Index >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, src0Index);
				VmReg* src0 = &registers[src0Index];
				u32 src1Index = frameFirstReg + frameCode[frameIp+3];
				if (src1Index >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, src1Index);
				VmReg* src1 = &registers[src1Index];
				dst.as_u64 = src0.as_u64 + src1.as_u64;
				dst.pointer = src0.pointer;
				if (src1.pointer.isDefined) return setTrap(VmStatus.ERR_PTR_SRC1);
				frameIp += 4;
				return;

			case sub_i64:
				u32 dstIndex = frameFirstReg + frameCode[frameIp+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				VmReg* dst = &registers[dstIndex];
				u32 src0Index = frameFirstReg + frameCode[frameIp+2];
				if (src0Index >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, src0Index);
				VmReg* src0 = &registers[src0Index];
				u32 src1Index = frameFirstReg + frameCode[frameIp+3];
				if (src1Index >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, src1Index);
				VmReg* src1 = &registers[src1Index];
				dst.as_u64 = src0.as_u64 - src1.as_u64;
				if (src0.pointer == src1.pointer)
					dst.pointer = AllocId();
				else if (src1.pointer.isUndefined)
					dst.pointer = AllocId();
				else
					return setTrap(VmStatus.ERR_PTR_SRC1);
				frameIp += 4;
				return;

			case const_s8:
				u32 dstIndex = frameFirstReg + frameCode[frameIp+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				VmReg* dst = &registers[dstIndex];
				i8 imm = frameCode[frameIp+2];
				dst.as_s64 = imm;
				dst.pointer = AllocId();
				frameIp += 3;
				return;

			case load_m8:
			case load_m16:
			case load_m32:
			case load_m64:
				u32 size = 1 << (op - load_m8);

				u32 dstIndex = frameFirstReg + frameCode[frameIp+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				VmReg* dst = &registers[dstIndex];

				u32 srcIndex = frameFirstReg + frameCode[frameIp+2];
				if (srcIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, srcIndex);
				VmReg* src = &registers[srcIndex];

				if (src.pointer.isUndefined) return setTrap(VmStatus.ERR_LOAD_NOT_PTR);
				if (!isMemoryReadable(src.pointer.kind)) return setTrap(VmStatus.ERR_LOAD_NO_READ_PERMISSION);

				if (!isPointerValid(src.pointer)) return setTrap(VmStatus.ERR_LOAD_INVALID_POINTER);

				Memory* mem = &memories[src.pointer.kind];
				Allocation* alloc = &mem.allocations[src.pointer.index];
				u8* memory = mem.memory[].ptr;

				i64 offset = src.as_s64;
				if (offset < 0) return setTrap(VmStatus.ERR_LOAD_OOB);
				if (offset + size > alloc.size) return setTrap(VmStatus.ERR_LOAD_OOB);

				size_t* initBits = cast(size_t*)&mem.initBitmap.front();
				size_t numInitedBytes = popcntBitRange(initBits, alloc.offset + cast(u32)offset, alloc.offset + cast(u32)offset + size);
				if (numInitedBytes != size) return setTrap(VmStatus.ERR_LOAD_UNINIT);

				// allocation size is never bigger than u32.max, so it is safe to cast valid offset to u32
				if (ptrSize.inBytes == size && offset % size == 0) {
					// this can be a pointer load
					dst.pointer = pointerGet(mem, alloc, cast(u32)offset);
				} else {
					dst.pointer = AllocId();
				}

				switch(op) {
					case load_m8:  dst.as_u64 = *cast( u8*)(memory + alloc.offset + offset); break;
					case load_m16: dst.as_u64 = *cast(u16*)(memory + alloc.offset + offset); break;
					case load_m32: dst.as_u64 = *cast(u32*)(memory + alloc.offset + offset); break;
					case load_m64: dst.as_u64 = *cast(u64*)(memory + alloc.offset + offset); break;
					default: assert(false);
				}

				frameIp += 3;
				return;

			case store_m8:
			case store_m16:
			case store_m32:
			case store_m64:
				u32 size = 1 << (op - store_m8);

				u32 dstIndex = frameFirstReg + frameCode[frameIp+1];
				if (dstIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, dstIndex);
				VmReg* dst = &registers[dstIndex];

				u32 srcIndex = frameFirstReg + frameCode[frameIp+2];
				if (srcIndex >= registers.length) return setTrap(VmStatus.ERR_REGISTER_OOB, srcIndex);
				VmReg* src = &registers[srcIndex];

				if (dst.pointer.isUndefined) return setTrap(VmStatus.ERR_STORE_NOT_PTR);
				if (!isMemoryWritable(dst.pointer.kind)) return setTrap(VmStatus.ERR_STORE_NO_WRITE_PERMISSION);

				Memory* mem = &memories[dst.pointer.kind];
				Allocation* alloc = &mem.allocations[dst.pointer.index];

				i64 offset = dst.as_s64;
				if (offset < 0) return setTrap(VmStatus.ERR_STORE_OOB);
				if (offset + size > alloc.size) return setTrap(VmStatus.ERR_STORE_OOB);

				// allocation size is never bigger than u32.max, so it is safe to cast valid offset to u32
				// Note: this part should execute before bytes are written, because we need original data in trap handler
				if (ptrSize.inBytes == size) {
					// this can be a pointer store
					if (src.pointer.isDefined) {
						// Pointer stores must be aligned
						if (offset % size != 0) return setTrap(VmStatus.ERR_STORE_PTR_UNALIGNED);
						// Mutate
						pointerPut(mem, alloc, cast(u32)offset, src.pointer);
					} else if (offset % size == 0) {
						// Erase pointer if write is aligned
						pointerRemove(mem, alloc, cast(u32)offset);
					}
				}

				u8* memory = mem.memory[].ptr;
				switch(op) {
					case store_m8:  *cast( u8*)(memory+alloc.offset+offset) = src.as_u8;  break;
					case store_m16: *cast(u16*)(memory+alloc.offset+offset) = src.as_u16; break;
					case store_m32: *cast(u32*)(memory+alloc.offset+offset) = src.as_u32; break;
					case store_m64: *cast(u64*)(memory+alloc.offset+offset) = src.as_u64; break;
					default: assert(false);
				}

				// mark bytes as initialized
				mem.markInitBits(cast(u32)(alloc.offset + offset), size, true);

				frameIp += 3;
				return;
		}
	}

	private void setTrap(VmStatus status, u64 data = 0) {
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
		u32 firstReg = frameFirstReg;

		sink("     [");
		foreach(i, reg; registers[firstReg..$]) {
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

	// No new line or dot at the end of the message
	void format_vm_error(scope SinkDelegate sink) {
		if (status == VmStatus.OK) return;

		u8* code = frameCode;
		u32 firstReg = frameFirstReg;

		final switch(status) with(VmStatus) {
			case OK:
				sink("ok");
				break;

			case ERR_TRAP:
				sink("trap instruction reached");
				break;

			case ERR_COND_OOB:
				sink.formattedWrite("Invalid condition %s, max condition is %s", errData, VmBinCond.max);
				break;

			case ERR_CMP_DIFFERENT_PTR:
				VmReg* dst  = &registers[firstReg + code[frameIp+2]];
				VmReg* src0 = &registers[firstReg + code[frameIp+3]];
				VmReg* src1 = &registers[firstReg + code[frameIp+4]];
				sink.formattedWrite("Cannot compare different pointers\n  r%s: %s\n  r%s: %s\n  r%s: %s",
					code[frameIp+2], *dst,
					code[frameIp+3], *src0,
					code[frameIp+4], *src1);
				break;

			case ERR_CMP_REQUIRES_NO_PTR:
				VmReg* dst  = &registers[firstReg + code[frameIp+2]];
				VmReg* src0 = &registers[firstReg + code[frameIp+3]];
				VmReg* src1 = &registers[firstReg + code[frameIp+4]];
				sink.formattedWrite("Compare operation expects no pointers\n  r%s: %s\n  r%s: %s\n  r%s: %s",
					code[frameIp+2], *dst,
					code[frameIp+3], *src0,
					code[frameIp+4], *src1);
				break;

			case ERR_REGISTER_OOB:
				sink.formattedWrite("Trying to access register out of bounds of register stack.\n  Num frame registers: %s\n  Invalid register: r%s",
					registers.length - firstReg, errData - firstReg);
				break;

			case ERR_PTR_SRC1:
				VmReg* dst  = &registers[firstReg + code[frameIp+1]];
				VmReg* src0 = &registers[firstReg + code[frameIp+2]];
				VmReg* src1 = &registers[firstReg + code[frameIp+3]];

				sink.formattedWrite("add.i64 can only contain pointers in the first argument.\n  r%s: %s\n  r%s: %s\n  r%s: %s",
					code[frameIp+1], *dst,
					code[frameIp+2], *src0,
					code[frameIp+3], *src1);
				break;

			case ERR_STORE_NO_WRITE_PERMISSION:
				VmReg* dst = &registers[firstReg + code[frameIp+1]];
				VmReg* src = &registers[firstReg + code[frameIp+2]];

				sink.formattedWrite("Writing to %s pointer is disabled.\n  r%s: %s\n  r%s: %s",
					memoryKindString[dst.pointer.kind],
					code[frameIp+1], *dst,
					code[frameIp+2], *src);
				break;

			case ERR_LOAD_NO_READ_PERMISSION:
				VmReg* dst = &registers[firstReg + code[frameIp+1]];
				VmReg* src = &registers[firstReg + code[frameIp+2]];

				sink.formattedWrite("Reading from %s pointer is disabled.\n  r%s: %s\n  r%s: %s",
					memoryKindString[src.pointer.kind],
					code[frameIp+1], *dst,
					code[frameIp+2], *src);
				break;

			case ERR_STORE_NOT_PTR:
				VmReg* dst = &registers[firstReg + code[frameIp+1]];

				sink.formattedWrite("Writing to non-pointer value (r%s:%s)", code[frameIp+1], *dst);
				break;

			case ERR_LOAD_NOT_PTR:
				VmReg* src = &registers[firstReg + code[frameIp+2]];
				sink.formattedWrite("Reading from non-pointer value (r%s:%s)", code[frameIp+2], *src);
				break;

			case ERR_LOAD_INVALID_POINTER:
				VmReg* src = &registers[firstReg + code[frameIp+2]];
				sink.formattedWrite("Reading from invalid pointer (r%s:%s)", code[frameIp+2], *src);
				break;

			case ERR_STORE_OOB:
				u8 op = code[frameIp+0];
				u32 size = 1 << (op - VmOpcode.store_m8);
				VmReg* dst = &registers[firstReg + code[frameIp+1]];
				Memory* mem = &memories[dst.pointer.kind];
				Allocation* alloc = &mem.allocations[dst.pointer.index];

				i64 offset = dst.as_s64;

				sink.formattedWrite("Writing outside of the allocation %s\nWriting %s bytes at offset %s, to allocation of %s bytes",
					dst.pointer,
					size,
					offset,
					alloc.size);
				break;

			case ERR_STORE_PTR_UNALIGNED:
				u8 op = code[frameIp+0];
				u32 size = 1 << (op - VmOpcode.store_m8);
				VmReg* dst = &registers[firstReg + code[frameIp+1]];
				Memory* mem = &memories[dst.pointer.kind];
				Allocation* alloc = &mem.allocations[dst.pointer.index];

				u64 offset = dst.as_u64;

				sink.formattedWrite("Writing pointer value (r%s:%s) to an unaligned offset (0x%X)",
					code[frameIp+1], *dst,
					offset);
				break;

			case ERR_LOAD_OOB:
				u8 op = code[frameIp+0];
				u32 size = 1 << (op - VmOpcode.load_m8);
				VmReg* src = &registers[firstReg + code[frameIp+2]];
				Memory* mem = &memories[src.pointer.kind];
				Allocation* alloc = &mem.allocations[src.pointer.index];

				i64 offset = src.as_s64;

				sink.formattedWrite("Reading outside of the allocation %s\nReading %s bytes at offset %s, from allocation of %s bytes",
					src.pointer,
					size,
					offset,
					alloc.size);
				break;

			case ERR_LOAD_UNINIT:
				u8 op = code[frameIp+0];
				u32 size = 1 << (op - VmOpcode.load_m8);
				VmReg* src = &registers[firstReg + code[frameIp+2]];
				Memory* mem = &memories[src.pointer.kind];
				Allocation* alloc = &mem.allocations[src.pointer.index];

				u64 offset = src.as_u64;

				sink.formattedWrite("Reading uninitialized memory from allocation (r%s:%s)\n  Reading %s bytes at offset %s",
					code[frameIp+2], *src,
					size,
					offset);

				printMem(sink, src.pointer, cast(u32)offset, size, 16, 2);
				break;
		}
	}
}

enum VmStatus : u8 {
	OK,
	ERR_TRAP,
	ERR_COND_OOB,
	ERR_CMP_DIFFERENT_PTR,
	ERR_CMP_REQUIRES_NO_PTR,
	ERR_REGISTER_OOB,
	ERR_PTR_SRC1,
	ERR_STORE_NO_WRITE_PERMISSION,
	ERR_LOAD_NO_READ_PERMISSION,
	ERR_STORE_NOT_PTR,
	ERR_LOAD_NOT_PTR,
	ERR_STORE_OOB,
	ERR_STORE_PTR_UNALIGNED,
	ERR_LOAD_OOB,
	ERR_LOAD_UNINIT,
	ERR_LOAD_INVALID_POINTER,
}

struct VmFunction {
	@nogc nothrow:

	VmFuncKind kind;
	u8 numResults;
	u8 numParameters;
	u8 numLocals;
	u32 numTotalRegs() { return numResults + numParameters + numLocals; }
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

	u32 funcIndex;
	u32 ip;
	// index of the first register
	u32 firstRegister;
}
