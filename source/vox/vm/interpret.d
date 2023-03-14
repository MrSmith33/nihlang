/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.interpret;

import vox.lib;
import vox.vm;

@nogc nothrow:

// Invariant: when trap happens, VM state should remain as if instruction was not executed
void vmStep(ref VmState vm) {
	pragma(inline, true);
	VmOpcode op = cast(VmOpcode)vm.code[vm.ip+0];

	final switch(op) with(VmOpcode) {
		case ret: return instr_ret(vm);
		case trap: return instr_trap(vm);
		case jump: return instr_jump(vm);
		case branch: return instr_branch(vm);
		case branch_zero: return instr_branch_zero(vm);
		case branch_ge: return instr_branch_ge(vm);
		case branch_le_imm8: return instr_branch_le_imm8(vm);
		case branch_gt_imm8: return instr_branch_gt_imm8(vm);
		case call: return instr_call(vm);
		case tail_call: return instr_tail_call(vm);
		case mov: return instr_mov(vm);
		case cmp: return instr_cmp(vm);
		case add_i64: return instr_add_i64(vm);
		case add_i64_imm8: return instr_add_i64_imm8(vm);
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
		vm.status = VmStatus.FINISHED;
		vm.func = 0;
		vm.ip = 0;
		vm.code = null;
	} else {
		VmFrame* frame = &vm.callerFrames.back();
		vm.regs -= frame.regOffset;
		vm.func = frame.func;
		vm.ip = frame.ip;
		vm.code = vm.functions[vm.func].code[].ptr;
		vm.callerFrames.unput(1);
		vm.popRegisters(frame.regOffset);
	}
	//++vm.numCalls;
}

void instr_trap(ref VmState vm) {
	pragma(inline, true);
	vm.setTrap(VmStatus.ERR_TRAP);
}
void instr_jump(ref VmState vm) {
	pragma(inline, true);
	i32 offset = *cast(i32*)&vm.code[vm.ip+1];
	vm.ip += offset + 5;
}
void instr_branch(ref VmState vm) {
	pragma(inline, true);
	VmReg* src = &vm.regs[vm.code[vm.ip+1]];

	i32 offset = *cast(i32*)&vm.code[vm.ip+2];

	if (src.as_u64 || src.pointer.isDefined) {
		vm.ip += offset + 6;
		return;
	}

	vm.ip += 6;
}
void instr_branch_zero(ref VmState vm) {
	pragma(inline, true);
	VmReg* src = &vm.regs[vm.code[vm.ip+1]];

	i32 offset = *cast(i32*)&vm.code[vm.ip+2];

	if (src.as_u64 == 0 && src.pointer.isUndefined) {
		vm.ip += offset + 6;
		return;
	}

	vm.ip += 6;
}
void instr_branch_ge(ref VmState vm) {
	pragma(inline, true);

	VmReg* src0 = &vm.regs[vm.code[vm.ip+1]];
	VmReg* src1 = &vm.regs[vm.code[vm.ip+2]];
	i32 offset = *cast(i32*)&vm.code[vm.ip+3];

	if (src0.as_u64 >= src1.as_u64) {
		vm.ip += offset + 7;
		return;
	}

	vm.ip += 7;
}
void instr_branch_le_imm8(ref VmState vm) {
	pragma(inline, true);

	VmReg* src0 = &vm.regs[vm.code[vm.ip+1]];
	i64 src1 = cast(i8)vm.code[vm.ip+2];
	i32 offset = *cast(i32*)&vm.code[vm.ip+3];

	if (src0.as_u64 <= src1) {
		vm.ip += offset + 7;
		return;
	}

	vm.ip += 7;
}
void instr_branch_gt_imm8(ref VmState vm) {
	pragma(inline, true);

	VmReg* src0 = &vm.regs[vm.code[vm.ip+1]];
	i64 src1 = cast(i8)vm.code[vm.ip+2];
	i32 offset = *cast(i32*)&vm.code[vm.ip+3];

	if (src0.as_u64 > src1) {
		vm.ip += offset + 7;
		return;
	}

	vm.ip += 7;
}
void instr_call(ref VmState vm) {
	pragma(inline, true);
	u8  arg0_idx = vm.code[vm.ip+1];
	u8  num_args = vm.code[vm.ip+2];
	FuncId calleeId = *cast(FuncId*)&vm.code[vm.ip+3];

	VmFunction* caller = &vm.functions[vm.func];

	if(calleeId >= vm.functions.length) panic("Invalid function index (%s), only %s functions exist", calleeId, vm.functions.length);
	VmFunction* callee = &vm.functions[calleeId];

	if(arg0_idx + num_args > 256) panic("Invalid stack setup"); // TODO validation

	// modify current frame here, before pushing new one, as reallocation of callerFrames might happen
	vm.ip += 7;

	if (callee.kind == VmFuncKind.external && callee.external == null) panic("VmFunction.external is not set");

	VmFrame callerFrame = {
		func : vm.func,
		ip : vm.ip,
		regOffset : arg0_idx,
	};
	vm.callerFrames.put(*vm.allocator, callerFrame);

	vm.func = calleeId;
	vm.ip = 0;
	u32 regIndex = vm.frameFirstReg;
	vm.pushRegisters(arg0_idx);
	// calculate regs from scratch in case of reallocation
	vm.regs = &vm.registers[regIndex + arg0_idx];

	final switch(callee.kind) {
		case VmFuncKind.bytecode:
			vm.code = callee.code[].ptr;
			return;

		case VmFuncKind.external:
			vm.code = null;
			// call
			callee.external(vm, callee.externalUserData);
			// restore
			instr_ret(vm);
			return;
	}
}
void instr_tail_call(ref VmState vm) {
	pragma(inline, true);
	u8  num_args = vm.code[vm.ip+1];
	u32 calleeId = *cast(i32*)&vm.code[vm.ip+2];

	VmFunction* caller = &vm.functions[vm.func];

	if(calleeId >= vm.functions.length) panic("Invalid function index (%s), only %s functions exist", calleeId, vm.functions.length);
	VmFunction* callee = &vm.functions[calleeId];

	if(num_args > 256) panic("Invalid stack setup"); // TODO validation
	if (callee.kind == VmFuncKind.external && callee.external == null) panic("VmFunction.external is not set");

	// frame is not pushed
	// vm.regs remains the same
	vm.func = calleeId;
	vm.ip = 0;

	final switch(callee.kind) {
		case VmFuncKind.bytecode:
			vm.code = callee.code[].ptr;
			return;

		case VmFuncKind.external:
			vm.code = null;
			// call
			callee.external(vm, callee.externalUserData);
			// restore
			instr_ret(vm);
			return;
	}
}
void instr_mov(ref VmState vm) {
	pragma(inline, true);
	VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
	VmReg* src = &vm.regs[vm.code[vm.ip+2]];
	*dst = *src;
	vm.ip += 3;
}
// u8 op, VmBinCond cmp_op, u8 dst, u8 src0, u8 src1
void instr_cmp(ref VmState vm) {
	pragma(inline, true);
	VmBinCond cond = cast(VmBinCond)vm.code[vm.ip+1];
	if (cond > VmBinCond.max) return vm.setTrap(VmStatus.ERR_COND_OOB, cond);

	VmReg* dst = &vm.regs[vm.code[vm.ip+2]];
	VmReg* src0 = &vm.regs[vm.code[vm.ip+3]];
	VmReg* src1 = &vm.regs[vm.code[vm.ip+4]];

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
	vm.ip += 5;
}
void instr_add_i64(ref VmState vm) {
	pragma(inline, true);
	VmReg* dst  = &vm.regs[vm.code[vm.ip+1]];
	VmReg* src0 = &vm.regs[vm.code[vm.ip+2]];
	VmReg* src1 = &vm.regs[vm.code[vm.ip+3]];
	dst.as_u64 = src0.as_u64 + src1.as_u64;
	dst.pointer = src0.pointer;
	if (src1.pointer.isDefined) return vm.setTrap(VmStatus.ERR_PTR_SRC1);
	vm.ip += 4;
}
void instr_add_i64_imm8(ref VmState vm) {
	pragma(inline, true);
	VmReg* dst  = &vm.regs[vm.code[vm.ip+1]];
	VmReg* src0 = &vm.regs[vm.code[vm.ip+2]];
	i64 src1 = cast(i8)vm.code[vm.ip+3];
	dst.as_u64 = src0.as_s64 + src1;
	dst.pointer = src0.pointer;
	vm.ip += 4;
}
void instr_sub_i64(ref VmState vm) {
	pragma(inline, true);
	VmReg* dst  = &vm.regs[vm.code[vm.ip+1]];
	VmReg* src0 = &vm.regs[vm.code[vm.ip+2]];
	VmReg* src1 = &vm.regs[vm.code[vm.ip+3]];
	dst.as_u64 = src0.as_u64 - src1.as_u64;
	if (src0.pointer == src1.pointer)
		dst.pointer = AllocId();
	else if (src1.pointer.isUndefined)
		dst.pointer = AllocId();
	else
		return vm.setTrap(VmStatus.ERR_PTR_SRC1);
	vm.ip += 4;
}
void instr_const_s8(ref VmState vm) {
	pragma(inline, true);
	VmReg* dst  = &vm.regs[vm.code[vm.ip+1]];
	i8 imm = vm.code[vm.ip+2];
	dst.as_s64 = imm;
	dst.pointer = AllocId();
	vm.ip += 3;
}
void instr_load(ref VmState vm) {
	pragma(inline, true);
	VmOpcode op = cast(VmOpcode)vm.code[vm.ip+0];
	u32 size = 1 << (op - VmOpcode.load_m8);

	VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
	VmReg* src = &vm.regs[vm.code[vm.ip+2]];

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

	vm.ip += 3;
}
void instr_load_m8(ref VmState vm) {
	pragma(inline, true);
	enum u32 size = 1;

	VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
	VmReg* src = &vm.regs[vm.code[vm.ip+2]];

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

	vm.ip += 3;
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
	VmOpcode op = cast(VmOpcode)vm.code[vm.ip+0];
	u32 size = 1 << (op - VmOpcode.store_m8);

	VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
	VmReg* src = &vm.regs[vm.code[vm.ip+2]];

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

	vm.ip += 3;
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
