/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.interpret;

import vox.lib;
import vox.vm;

@nogc nothrow:

// Invariant: when trap happens, VM state should remain as if instruction was not executed
void vmStep(ref VmState vm) {
	VmOpcode op = cast(VmOpcode)vm.frameCode[vm.frameIp+0];

	final switch(op) with(VmOpcode) {
		case ret: return instr_ret(vm);
		case trap: return instr_trap(vm);
		case jump: return instr_jump(vm);
		case branch: return instr_branch(vm);
		case call: return instr_call(vm);
		case mov: return instr_mov(vm);
		case cmp: return instr_cmp(vm);
		case add_i64: return instr_add_i64(vm);
		case sub_i64: return instr_sub_i64(vm);
		case const_s8: return instr_const_s8(vm);

		case load_m8: return instr_load(vm);
		case load_m16: return instr_load(vm);
		case load_m32: return instr_load(vm);
		case load_m64: return instr_load(vm);

		case store_m8: return instr_store(vm);
		case store_m16: return instr_store(vm);
		case store_m32: return instr_store(vm);
		case store_m64: return instr_store(vm);
	}
}

void instr_ret(ref VmState vm) {
	pragma(inline, true);
	if (vm.callerFrames.length == 0) {
		vm.isRunning = false;
		vm.frameFirstReg = 0;
		vm.frameFuncIndex = 0;
		vm.frameIp = 0;
		vm.frameCode = null;
	} else {
		VmFrame* frame = &vm.callerFrames.back();
		vm.frameFirstReg = frame.firstRegister;
		vm.frameFuncIndex = frame.funcIndex;
		vm.frameIp = frame.ip;
		vm.frameCode = vm.functions[vm.frameFuncIndex].code[].ptr;
		vm.callerFrames.unput(1);
	}
	vm.popRegisters(vm.registers.length - vm.frameFirstReg - 256);
	//++vm.numCalls;
}

void instr_trap(ref VmState vm) {
	pragma(inline, true);
	vm.setTrap(VmStatus.ERR_TRAP);
}
void instr_jump(ref VmState vm) {
	pragma(inline, true);
	i32 offset = *cast(i32*)&vm.frameCode[vm.frameIp+1];
	vm.frameIp += offset + 5;
}
void instr_branch(ref VmState vm) {
	pragma(inline, true);
	u32 srcIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+1];
	VmReg* src = &vm.registers[srcIndex];

	i32 offset = *cast(i32*)&vm.frameCode[vm.frameIp+2];

	if (src.as_u64 || src.pointer.isDefined) {
		vm.frameIp += offset + 6;
		return;
	}

	vm.frameIp += 6;
}
void instr_call(ref VmState vm) {
	pragma(inline, true);
	u8  arg0_idx = vm.frameCode[vm.frameIp+1];
	u8  num_args = vm.frameCode[vm.frameIp+2];
	u32 funcIndex = *cast(i32*)&vm.frameCode[vm.frameIp+3];

	VmFunction* caller = &vm.functions[vm.frameFuncIndex];

	if(funcIndex >= vm.functions.length) panic("Invalid function index (%s), only %s functions exist", funcIndex, vm.functions.length);
	VmFunction* callee = &vm.functions[funcIndex];

	if(arg0_idx + num_args > 256) panic("Invalid stack setup"); // TODO validation

	// modify current frame here, before pushing new one, as reallocation of callerFrames might happen
	vm.frameIp += 7;

	if (callee.kind == VmFuncKind.external && callee.external == null) panic("VmFunction.external is not set");

	VmFrame callerFrame = {
		funcIndex : vm.frameFuncIndex,
		ip : vm.frameIp,
		firstRegister : vm.frameFirstReg,
	};
	vm.callerFrames.put(*vm.allocator, callerFrame);

	vm.frameFirstReg += arg0_idx;
	vm.frameFuncIndex = funcIndex;
	vm.frameIp = 0;
	vm.pushRegisters(arg0_idx);

	final switch(callee.kind) {
		case VmFuncKind.bytecode:
			vm.frameCode = callee.code[].ptr;
			return;

		case VmFuncKind.external:
			vm.frameCode = null;
			// call
			callee.external(vm, callee.externalUserData);
			// restore
			VmFrame* frame = &vm.callerFrames.back();
			vm.frameFirstReg = frame.firstRegister;
			vm.frameFuncIndex = frame.funcIndex;
			vm.frameIp = frame.ip;
			vm.frameCode = caller.code[].ptr;
			vm.popRegisters(vm.registers.length - vm.frameFirstReg - 256);
			vm.callerFrames.unput(1);
			return;
	}
}
void instr_mov(ref VmState vm) {
	pragma(inline, true);
	u32 dstIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+1];
	u32 srcIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+2];
	vm.registers[dstIndex] = vm.registers[srcIndex];
	vm.frameIp += 3;
}
// u8 op, VmBinCond cmp_op, u8 dst, u8 src0, u8 src1
void instr_cmp(ref VmState vm) {
	pragma(inline, true);
	VmBinCond cond = cast(VmBinCond)vm.frameCode[vm.frameIp+1];
	if (cond > VmBinCond.max) return vm.setTrap(VmStatus.ERR_COND_OOB, cond);

	u32 dstIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+2];
	VmReg* dst = &vm.registers[dstIndex];

	u32 src0Index = vm.frameFirstReg + vm.frameCode[vm.frameIp+3];
	VmReg* src0 = &vm.registers[src0Index];

	u32 src1Index = vm.frameFirstReg + vm.frameCode[vm.frameIp+4];
	VmReg* src1 = &vm.registers[src1Index];

	final switch(cond) with(VmBinCond) {
		case m64_eq:
			dst.as_u64 = src0.as_u64 == src1.as_u64 && src0.pointer == src1.pointer;
			break;
		case m64_ne:
			dst.as_u64 = src0.as_u64 != src1.as_u64 || src0.pointer != src1.pointer;
			break;
		case u64_gt:
			if (src0.pointer != src1.pointer) return vm.setTrap(VmStatus.ERR_CMP_DIFFERENT_PTR);
			dst.as_u64 = src0.as_u64 >  src1.as_u64;
			break;
		case u64_ge:
			if (src0.pointer != src1.pointer) return vm.setTrap(VmStatus.ERR_CMP_DIFFERENT_PTR);
			dst.as_u64 = src0.as_u64 >= src1.as_u64;
			break;
		case s64_gt:
			if (src0.pointer.isDefined || src1.pointer.isDefined) return vm.setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
			dst.as_u64 = src0.as_s64 >  src1.as_s64;
			break;
		case s64_ge:
			if (src0.pointer.isDefined || src1.pointer.isDefined) return vm.setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
			dst.as_u64 = src0.as_s64 >= src1.as_s64;
			break;

		case f32_gt:
			if (src0.pointer.isDefined || src1.pointer.isDefined) return vm.setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
			dst.as_u64 = src0.as_f32 >  src1.as_f32;
			break;
		case f32_ge:
			if (src0.pointer.isDefined || src1.pointer.isDefined) return vm.setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
			dst.as_u64 = src0.as_f32 >= src1.as_f32;
			break;
		case f64_gt:
			if (src0.pointer.isDefined || src1.pointer.isDefined) return vm.setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
			dst.as_u64 = src0.as_f64 >  src1.as_f64;
			break;
		case f64_ge:
			if (src0.pointer.isDefined || src1.pointer.isDefined) return vm.setTrap(VmStatus.ERR_CMP_REQUIRES_NO_PTR);
			dst.as_u64 = src0.as_f64 >= src1.as_f64;
			break;
	}

	dst.pointer = AllocId();
	vm.frameIp += 5;
}
void instr_add_i64(ref VmState vm) {
	pragma(inline, true);
	u32 dstIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+1];
	VmReg* dst = &vm.registers[dstIndex];
	u32 src0Index = vm.frameFirstReg + vm.frameCode[vm.frameIp+2];
	VmReg* src0 = &vm.registers[src0Index];
	u32 src1Index = vm.frameFirstReg + vm.frameCode[vm.frameIp+3];
	VmReg* src1 = &vm.registers[src1Index];
	dst.as_u64 = src0.as_u64 + src1.as_u64;
	dst.pointer = src0.pointer;
	if (src1.pointer.isDefined) return vm.setTrap(VmStatus.ERR_PTR_SRC1);
	vm.frameIp += 4;
}
void instr_sub_i64(ref VmState vm) {
	pragma(inline, true);
	u32 dstIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+1];
	VmReg* dst = &vm.registers[dstIndex];
	u32 src0Index = vm.frameFirstReg + vm.frameCode[vm.frameIp+2];
	VmReg* src0 = &vm.registers[src0Index];
	u32 src1Index = vm.frameFirstReg + vm.frameCode[vm.frameIp+3];
	VmReg* src1 = &vm.registers[src1Index];
	dst.as_u64 = src0.as_u64 - src1.as_u64;
	if (src0.pointer == src1.pointer)
		dst.pointer = AllocId();
	else if (src1.pointer.isUndefined)
		dst.pointer = AllocId();
	else
		return vm.setTrap(VmStatus.ERR_PTR_SRC1);
	vm.frameIp += 4;
}
void instr_const_s8(ref VmState vm) {
	pragma(inline, true);
	u32 dstIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+1];
	VmReg* dst = &vm.registers[dstIndex];
	i8 imm = vm.frameCode[vm.frameIp+2];
	dst.as_s64 = imm;
	dst.pointer = AllocId();
	vm.frameIp += 3;
}
void instr_load(ref VmState vm) {
	pragma(inline, true);
	VmOpcode op = cast(VmOpcode)vm.frameCode[vm.frameIp+0];
	u32 size = 1 << (op - VmOpcode.load_m8);

	u32 dstIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+1];
	VmReg* dst = &vm.registers[dstIndex];

	u32 srcIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+2];
	VmReg* src = &vm.registers[srcIndex];

	if (src.pointer.isUndefined) return vm.setTrap(VmStatus.ERR_LOAD_NOT_PTR);
	if (!vm.isMemoryReadable(src.pointer.kind)) return vm.setTrap(VmStatus.ERR_LOAD_NO_READ_PERMISSION);

	if (!vm.isPointerValid(src.pointer)) return vm.setTrap(VmStatus.ERR_LOAD_INVALID_POINTER);

	Memory* mem = &vm.memories[src.pointer.kind];
	Allocation* alloc = &mem.allocations[src.pointer.index];
	u8* memory = mem.memory[].ptr;

	i64 offset = src.as_s64;
	if (offset < 0) return vm.setTrap(VmStatus.ERR_LOAD_OOB);
	if (offset + size > alloc.size) return vm.setTrap(VmStatus.ERR_LOAD_OOB);

	size_t* initBits = cast(size_t*)&mem.initBitmap.front();
	size_t numInitedBytes = popcntBitRange(initBits, alloc.offset + cast(u32)offset, alloc.offset + cast(u32)offset + size);
	if (numInitedBytes != size) return vm.setTrap(VmStatus.ERR_LOAD_UNINIT);

	// allocation size is never bigger than u32.max, so it is safe to cast valid offset to u32
	if (vm.ptrSize.inBytes == size && offset % size == 0) {
		// this can be a pointer load
		dst.pointer = vm.pointerGet(mem, alloc, cast(u32)offset);
	} else {
		dst.pointer = AllocId();
	}

	switch(op) with(VmOpcode) {
		case load_m8:  dst.as_u64 = *cast( u8*)(memory + alloc.offset + offset); break;
		case load_m16: dst.as_u64 = *cast(u16*)(memory + alloc.offset + offset); break;
		case load_m32: dst.as_u64 = *cast(u32*)(memory + alloc.offset + offset); break;
		case load_m64: dst.as_u64 = *cast(u64*)(memory + alloc.offset + offset); break;
		default: assert(false);
	}

	vm.frameIp += 3;
}
void instr_load_m8(ref VmState vm) {
	pragma(inline, true);
	enum u32 size = 1;

	u32 dstIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+1];
	VmReg* dst = &vm.registers[dstIndex];

	u32 srcIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+2];
	VmReg* src = &vm.registers[srcIndex];

	if (src.pointer.isUndefined) return vm.setTrap(VmStatus.ERR_LOAD_NOT_PTR);
	if (!vm.isMemoryReadable(src.pointer.kind)) return vm.setTrap(VmStatus.ERR_LOAD_NO_READ_PERMISSION);

	if (!vm.isPointerValid(src.pointer)) return vm.setTrap(VmStatus.ERR_LOAD_INVALID_POINTER);

	Memory* mem = &vm.memories[src.pointer.kind];
	Allocation* alloc = &mem.allocations[src.pointer.index];
	u8* memory = mem.memory[].ptr;

	i64 offset = src.as_s64;
	if (offset < 0) return vm.setTrap(VmStatus.ERR_LOAD_OOB);
	if (offset + size > alloc.size) return vm.setTrap(VmStatus.ERR_LOAD_OOB);

	size_t* initBits = cast(size_t*)&mem.initBitmap.front();
	size_t numInitedBytes = popcntBitRange(initBits, alloc.offset + cast(u32)offset, alloc.offset + cast(u32)offset + size);
	if (numInitedBytes != size) return vm.setTrap(VmStatus.ERR_LOAD_UNINIT);

	dst.as_u64 = *cast( u8*)(memory + alloc.offset + offset);
	dst.pointer = AllocId();

	vm.frameIp += 3;
}
void instr_load_m16(ref VmState vm) {
	pragma(inline, true);

}
void instr_load_m32(ref VmState vm) {
	pragma(inline, true);

}
void instr_load_m64(ref VmState vm) {
	pragma(inline, true);

}
void instr_store(ref VmState vm) {
	pragma(inline, true);
	VmOpcode op = cast(VmOpcode)vm.frameCode[vm.frameIp+0];
	u32 size = 1 << (op - VmOpcode.store_m8);

	u32 dstIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+1];
	VmReg* dst = &vm.registers[dstIndex];

	u32 srcIndex = vm.frameFirstReg + vm.frameCode[vm.frameIp+2];
	VmReg* src = &vm.registers[srcIndex];

	if (dst.pointer.isUndefined) return vm.setTrap(VmStatus.ERR_STORE_NOT_PTR);
	if (!vm.isMemoryWritable(dst.pointer.kind)) return vm.setTrap(VmStatus.ERR_STORE_NO_WRITE_PERMISSION);

	Memory* mem = &vm.memories[dst.pointer.kind];
	Allocation* alloc = &mem.allocations[dst.pointer.index];

	i64 offset = dst.as_s64;
	if (offset < 0) return vm.setTrap(VmStatus.ERR_STORE_OOB);
	if (offset + size > alloc.size) return vm.setTrap(VmStatus.ERR_STORE_OOB);

	// allocation size is never bigger than u32.max, so it is safe to cast valid offset to u32
	// Note: this part should execute before bytes are written, because we need original data in trap handler
	if (vm.ptrSize.inBytes == size) {
		// this can be a pointer store
		if (src.pointer.isDefined) {
			// Pointer stores must be aligned
			if (offset % size != 0) return vm.setTrap(VmStatus.ERR_STORE_PTR_UNALIGNED);
			// Mutate
			vm.pointerPut(mem, alloc, cast(u32)offset, src.pointer);
		} else if (offset % size == 0) {
			// Erase pointer if write is aligned
			vm.pointerRemove(mem, alloc, cast(u32)offset);
		}
	}

	u8* memory = mem.memory[].ptr;
	switch(op) with(VmOpcode) {
		case store_m8:  *cast( u8*)(memory+alloc.offset+offset) = src.as_u8;  break;
		case store_m16: *cast(u16*)(memory+alloc.offset+offset) = src.as_u16; break;
		case store_m32: *cast(u32*)(memory+alloc.offset+offset) = src.as_u32; break;
		case store_m64: *cast(u64*)(memory+alloc.offset+offset) = src.as_u64; break;
		default: assert(false);
	}

	// mark bytes as initialized
	mem.markInitBits(cast(u32)(alloc.offset + offset), size, true);

	vm.frameIp += 3;
}
void instr_store_m8(ref VmState vm) {
	pragma(inline, true);

}
void instr_store_m16(ref VmState vm) {
	pragma(inline, true);

}
void instr_store_m32(ref VmState vm) {
	pragma(inline, true);

}
void instr_store_m64(ref VmState vm) {
	pragma(inline, true);

}
