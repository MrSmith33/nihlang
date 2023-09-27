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
		case trap: return instr_trap(vm);
		case jump: return instr_jump(vm);
		case branch: return instr_branch(vm);
		case branch_zero: return instr_branch_zero(vm);
		case branch_ge: return instr_branch_ge(vm);
		case branch_le_imm8: return instr_branch_le_imm8(vm);
		case branch_gt_imm8: return instr_branch_gt_imm8(vm);
		case stack_addr: return instr_stack_addr(vm);
		case stack_alloc: return instr_stack_alloc(vm);
		case call: return instr_call(vm);
		case tail_call: return instr_tail_call(vm);
		case ret: return instr_ret(vm);
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
		case memcopy: return instr_memcopy(vm);
	}
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
void instr_stack_addr(ref VmState vm) {
	pragma(inline, true);
	VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
	u8 slot_index = vm.code[vm.ip+2];
	assert(slot_index < vm.numFrameStackSlots);
	*dst = VmReg(AllocId(vm.frameFirstStackSlot + slot_index, MemoryKind.stack_mem));
	vm.ip += 3;
}
void instr_stack_alloc(ref VmState vm) {
	pragma(inline, true);
	SizeAndAlign sizeAlign = *cast(SizeAndAlign*)&vm.code[vm.ip+1];
	// TODO validation
	if(vm.numFrameStackSlots == u8.max) panic("Too many stack slots for single stack frame");
	vm.pushStackAlloc(sizeAlign);
	vm.ip += 5;
}
void instr_call(ref VmState vm) {
	pragma(inline, true);
	u8  arg0_idx = vm.code[vm.ip+1];
	u8  num_args = vm.code[vm.ip+2];
	FuncId calleeId = *cast(FuncId*)&vm.code[vm.ip+3];
	if(calleeId >= vm.functions.length) panic("Invalid function index (%s), only %s functions exist", calleeId, vm.functions.length);
	if(arg0_idx + num_args > 256) panic("Invalid stack setup"); // TODO validation
	instr_call_impl(vm, calleeId, arg0_idx);
}

// this function can be called from both bytecode function and from native function
void instr_call_impl(ref VmState vm, FuncId calleeId, u8 arg0_idx) {
	// Must be checked by the caller
	assert(calleeId < vm.functions.length);

	VmFunction* caller = &vm.functions[vm.func];
	VmFunction* callee = &vm.functions[calleeId];

	if (callee.kind == VmFuncKind.external && callee.external == null) panic("VmFunction.external is not set");

	u8 numStackParams = callee.numStackParams;
	// vm.numFrameStackSlots will be modified by pushStackAlloc below
	u8 numCallerStackSlots = cast(u8)(vm.numFrameStackSlots - numStackParams);
	if (callee.stackSlotSizes.length) {
		if (vm.numFrameStackSlots < numStackParams) {
			return vm.setTrap(VmStatus.ERR_CALL_INSUFFICIENT_STACK_ARGS, numStackParams);
		}
		SizeAndAlign* slotSizes = &callee.stackSlotSizes.front();
		// parameters: verify sizes
		bool sizesValid = true;
		foreach(i; 0..numStackParams) {
			// In the future we may allow bigger allocation than what was requested
			sizesValid = sizesValid && (slotSizes[i] == vm.stackSlots[i].sizeAlign);
		}
		if (!sizesValid) {
			return vm.setTrap(VmStatus.ERR_CALL_INVALID_STACK_ARG_SIZES);
		}
		// locals: allocate slots
		u8 numCalleeStackLocals = cast(u8)callee.stackSlotSizes.length;
		foreach(i; numStackParams..numCalleeStackLocals) {
			vm.pushStackAlloc(slotSizes[i]);
		}
	}

	// vm.ip already points to the next instruction for bytecode function
	VmFrame callerFrame = {
		func : vm.func,
		// native functions do not care about ip
		ip : vm.ip+7,
		regDelta : arg0_idx,
		numStackSlots : numCallerStackSlots,
	};
	vm.callerFrames.put(*vm.allocator, callerFrame);

	vm.func = calleeId;
	vm.ip = 0;
	u32 regIndex = vm.frameFirstReg;
	vm.pushRegisters(arg0_idx);
	vm.frameFirstStackSlot += numCallerStackSlots;
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
	u8  arg0_idx = vm.code[vm.ip+1];
	u8  num_args = vm.code[vm.ip+2];
	u32 calleeId = *cast(i32*)&vm.code[vm.ip+3];

	VmFunction* caller = &vm.functions[vm.func];

	if (calleeId >= vm.functions.length) panic("Invalid function index (%s), only %s functions exist", calleeId, vm.functions.length);
	VmFunction* callee = &vm.functions[calleeId];

	if (arg0_idx.u32 + num_args.u32 > 256) panic("Invalid stack setup"); // TODO validation
	if (callee.kind == VmFuncKind.external && callee.external == null) panic("VmFunction.external is not set");

	u8 numStackParams = callee.numStackParams;

	if (callee.stackSlotSizes.length) {
		if (vm.numFrameStackSlots < numStackParams) {
			return vm.setTrap(VmStatus.ERR_CALL_INSUFFICIENT_STACK_ARGS, numStackParams);
		}
		SizeAndAlign* slotSizes = &callee.stackSlotSizes.front();
		// parameters: verify sizes
		foreach(i; 0..numStackParams) {
			// In the future we may allow bigger allocation than what was requested
			if (slotSizes[i] == vm.stackSlots[i].sizeAlign) continue;
			return vm.setTrap(VmStatus.ERR_CALL_INVALID_STACK_ARG_SIZES);
		}
	}

	// vm.numFrameStackSlots will be modified by pushStackAlloc below
	u8 numCallerStackSlots = cast(u8)(vm.numFrameStackSlots - numStackParams);

	if (numCallerStackSlots) {
		// Caller stack slots are dropped
		DroppedStackSlots dropped = {
			// Argument regs are preserved
			preserve_regs_from  : arg0_idx,
			preserve_regs_to    : cast(u8)(arg0_idx + num_args),
			// Dropped stack slots
			slots_from : 0,
			slots_to   : numCallerStackSlots,
		};
		pre_drop_stack_range(vm, dropped);
		if (vm.status != VmStatus.RUNNING) return;

		Memory* mem = &vm.memories[MemoryKind.stack_mem];
		mem.popAndShiftAllocations(
			*vm.allocator,
			vm.frameFirstStackSlot,
			vm.frameFirstStackSlot + numCallerStackSlots);
	}

	u8 numCallerRegisters = arg0_idx;
	if (numCallerRegisters) {
		// Shift registers
		foreach(i; 0..callee.numRegParams) {
			vm.regs[i] = vm.regs[arg0_idx + i];
		}
	}

	if (callee.stackSlotSizes.length) {
		// locals: allocate slots
		u8 numCalleeStackLocals = cast(u8)callee.stackSlotSizes.length;
		SizeAndAlign* slotSizes = &callee.stackSlotSizes.front();
		foreach(i; numStackParams..numCalleeStackLocals) {
			vm.pushStackAlloc(slotSizes[i]);
		}
	}

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

// Also called at the end of native function call
void instr_ret(ref VmState vm) {
	pragma(inline, true);

	if (vm.numFrameStackSlots) {
		VmFunction* callee = &vm.functions[vm.func];
		DroppedStackSlots dropped = {
			preserve_regs_from  : 0,
			preserve_regs_to    : callee.numResults,
			slots_from : 0,
			slots_to   : vm.numFrameStackSlots,
		};
		pre_drop_stack_range(vm, dropped);
		if (vm.status != VmStatus.RUNNING) return;

		Memory* mem = &vm.memories[MemoryKind.stack_mem];
		mem.popAllocations(*vm.allocator, vm.numFrameStackSlots);
		vm.frameFirstStackSlot -= vm.numFrameStackSlots;
	}

	// we always have at least 1 frame, because initial native caller has its own frame
	assert(vm.callerFrames.length);
	VmFrame* frame = &vm.callerFrames.back();
	vm.ip = frame.ip;
	vm.func = frame.func;
	vm.regs -= frame.regDelta;
	if (vm.callerFrames.length == 1) {
		vm.status = VmStatus.FINISHED;
		vm.code = null;
	} else {
		vm.code = vm.functions[vm.func].code[].ptr;
	}

	vm.popRegisters(frame.regDelta);
	vm.frameFirstStackSlot -= frame.numStackSlots;

	// don't touch frame after unput
	vm.callerFrames.unput(1);
}

struct DroppedStackSlots {
	// Preserved registers
	// These registers are the ones that are to be preserved
	// arguments or results. They are checked to not contain
	// references to dropped stack slots
	u8 preserve_regs_from;
	u8 preserve_regs_to;
	// Dropped stack slots
	// These slots are checked for escaped refs
	// and then the references are removed from them
	u8 slots_from;
	u8 slots_to;
}

private void pre_drop_stack_range(ref VmState vm, DroppedStackSlots dropped) {
	// step 1: Check preserved regs for stack refs
	foreach(i; dropped.preserve_regs_from..dropped.preserve_regs_to) {
		VmReg val = vm.regs[i];
		if (val.pointer.isUndefined) continue;
		if (val.pointer.kind != MemoryKind.stack_mem) continue;
		if (val.pointer.index < vm.frameFirstStackSlot) continue;

		return vm.setTrap(VmStatus.ERR_ESCAPED_PTR_TO_STACK_IN_REG, i);
	}

	// step 2: Remove references in deleted stack slots
	u32 fromSlot = vm.frameFirstStackSlot + dropped.slots_from;
	u32 toSlot   = vm.frameFirstStackSlot + dropped.slots_to;
	Memory* mem = &vm.memories[MemoryKind.stack_mem];
	Allocation[] stackAllocs = mem.allocations[fromSlot..toSlot];
	// Decrement references from stackAllocs to stackAllocs
	changeLocalPointeeInRefs(vm, stackAllocs, -1, fromSlot, toSlot);

	// step 3: Check that all stack slots have 0 references
	foreach(i, ref Allocation alloc; stackAllocs) {
		if (alloc.numInRefs == 0) continue;

		// Restore references from stackAllocs to stackAllocs
		changeLocalPointeeInRefs(vm, stackAllocs, 1, fromSlot, toSlot);

		return vm.setTrap(VmStatus.ERR_ESCAPED_PTR_TO_STACK_IN_MEM, i);
	}

	// step 4: actually delete the references now
	// Restore refs, because pointerRemove decrements them
	changePointeeInRefs(vm, stackAllocs, 1);

	foreach(ref Allocation alloc; stackAllocs) {
		static if (OUT_REFS_PER_MEMORY) {
			if (alloc.numOutRefs == 0) continue;
		}
		foreach(u32 offset, AllocId target; AllocationRefIterator(mem, alloc, vm.ptrSize)) {
			vm.pointerRemove(mem, &alloc, offset);
		}
		static if (OUT_REFS_PER_ALLOCATION) {
			// Release memory buffer. Even when length == 0
			alloc.outRefs.free(*vm.allocator);
		}
	}
}

// Only modify inRef count of stackAllocs
private void changeLocalPointeeInRefs(ref VmState vm, Allocation[] stackAllocs, int delta, u32 fromSlot, u32 toSlot) {
	Memory* mem = &vm.memories[MemoryKind.stack_mem];
	foreach(ref Allocation alloc; stackAllocs) {
		if (alloc.numOutRefs == 0) continue;
		foreach(u32 offset, AllocId target; AllocationRefIterator(mem, alloc, vm.ptrSize)) {
			// skip non-stack targets
			if (target.kind != MemoryKind.stack_mem) continue;
			// skip targets outside of destroyed stack slot range
			if (target.index < fromSlot) continue;
			if (target.index >= toSlot) continue;
			vm.changeAllocInRef(target, delta);
		}
	}
}

private void changePointeeInRefs(ref VmState vm, Allocation[] stackAllocs, int delta) {
	Memory* mem = &vm.memories[MemoryKind.stack_mem];
	foreach(ref Allocation alloc; stackAllocs) {
		if (alloc.numOutRefs == 0) continue;
		foreach(u32 offset, AllocId target; AllocationRefIterator(mem, alloc, vm.ptrSize)) {
			vm.changeAllocInRef(target, delta);
		}
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
	// read src at the beginning, so writes to dst do not erase the data
	AllocId pointer = src.pointer;
	i64 offset      = src.as_s64;

	if (pointer.isUndefined) return vm.setTrap(VmStatus.ERR_SRC_NOT_PTR);
	if (!vm.isMemoryReadable(pointer.kind)) return vm.setTrap(VmStatus.ERR_NO_SRC_MEM_READ_PERMISSION);

	Memory* mem = &vm.memories[pointer.kind];
	Allocation* alloc = &mem.allocations[pointer.index];
	if (!alloc.isReadable) {
		if (!alloc.isPointerValid(pointer)) {
			return vm.setTrap(VmStatus.ERR_SRC_ALLOC_FREED);
		}
		return vm.setTrap(VmStatus.ERR_NO_SRC_ALLOC_READ_PERMISSION);
	}

	if (offset < 0) return vm.setTrap(VmStatus.ERR_READ_OOB);
	if (offset + size > alloc.sizeAlign.size) return vm.setTrap(VmStatus.ERR_READ_OOB);

	static if (SANITIZE_UNINITIALIZED_MEM) {
		size_t numInitedBytes = mem.countInitBits(alloc.offset + cast(u32)offset, size);
		if (numInitedBytes != size) return vm.setTrap(VmStatus.ERR_READ_UNINIT);
	}

	// overwrite dst after src
	// allocation size is never bigger than u32.max, so it is safe to cast valid offset to u32
	if (vm.ptrSize.inBytes == size && ((offset % size) == 0)) {
		// this can be a pointer load
		dst.pointer = vm.pointerGet(mem, alloc, cast(u32)offset);
	} else {
		dst.pointer = AllocId();
	}

	u8* memory = mem.memory[].ptr;
	switch(op) with(VmOpcode) {
		case load_m8:  dst.as_u64 = *cast( u8*)(memory + alloc.offset + offset); break;
		case load_m16: dst.as_u64 = *cast(u16*)(memory + alloc.offset + offset); break;
		case load_m32: dst.as_u64 = *cast(u32*)(memory + alloc.offset + offset); break;
		case load_m64: dst.as_u64 = *cast(u64*)(memory + alloc.offset + offset); break;
		default: assert(false);
	}

	vm.ip += 3;
}
void instr_store(ref VmState vm) {
	pragma(inline, true);
	VmOpcode op = cast(VmOpcode)vm.code[vm.ip+0];
	u32 size = 1 << (op - VmOpcode.store_m8);

	VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
	VmReg* src = &vm.regs[vm.code[vm.ip+2]];

	if (dst.pointer.isUndefined) return vm.setTrap(VmStatus.ERR_DST_NOT_PTR);
	if (!vm.isMemoryWritable(dst.pointer.kind)) return vm.setTrap(VmStatus.ERR_NO_DST_MEM_WRITE_PERMISSION);

	Memory* mem = &vm.memories[dst.pointer.kind];
	Allocation* alloc = &mem.allocations[dst.pointer.index];
	if (!alloc.isWritable) {
		if (!alloc.isPointerValid(dst.pointer)) {
			return vm.setTrap(VmStatus.ERR_DST_ALLOC_FREED);
		}
		return vm.setTrap(VmStatus.ERR_NO_DST_ALLOC_WRITE_PERMISSION);
	}

	i64 offset = dst.as_s64;
	if (offset < 0) return vm.setTrap(VmStatus.ERR_WRITE_OOB);
	if (offset + size > alloc.sizeAlign.size) return vm.setTrap(VmStatus.ERR_WRITE_OOB);

	// allocation size is never bigger than u32.max, so it is safe to cast valid offset to u32
	// Note: this part should execute before bytes are written, because we need original data in trap handler
	if (vm.ptrSize.inBytes == size) {
		// this can be a pointer store
		if (src.pointer.isDefined) {
			// Pointer stores must be aligned
			if (offset % size != 0) return vm.setTrap(VmStatus.ERR_WRITE_PTR_UNALIGNED);
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

	static if (SANITIZE_UNINITIALIZED_MEM) {
		// mark bytes as initialized
		mem.markInitBits(cast(u32)(alloc.offset + offset), size, true);
	}

	vm.ip += 3;
}

void instr_memcopy(ref VmState vm) {
	VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
	VmReg* src = &vm.regs[vm.code[vm.ip+2]];
	VmReg* len = &vm.regs[vm.code[vm.ip+3]];

	if (dst.pointer.isUndefined) return vm.setTrap(VmStatus.ERR_DST_NOT_PTR);
	if (!vm.isMemoryWritable(dst.pointer.kind)) return vm.setTrap(VmStatus.ERR_NO_DST_MEM_WRITE_PERMISSION);
	if (src.pointer.isUndefined) return vm.setTrap(VmStatus.ERR_SRC_NOT_PTR);
	if (!vm.isMemoryReadable(src.pointer.kind)) return vm.setTrap(VmStatus.ERR_NO_SRC_MEM_READ_PERMISSION);
	if (len.pointer.isDefined) return vm.setTrap(VmStatus.ERR_LEN_IS_PTR);

	Memory* dstMem = &vm.memories[dst.pointer.kind];
	Allocation* dstAlloc = &dstMem.allocations[dst.pointer.index];
	if (!dstAlloc.isWritable) {
		if (!dstAlloc.isPointerValid(dst.pointer)) {
			return vm.setTrap(VmStatus.ERR_DST_ALLOC_FREED);
		}
		return vm.setTrap(VmStatus.ERR_NO_DST_ALLOC_WRITE_PERMISSION);
	}

	i64 length = len.as_s64;

	i64 dstOffset = dst.as_s64;
	if (dstOffset < 0) return vm.setTrap(VmStatus.ERR_WRITE_OOB);
	if (dstOffset + length > dstAlloc.sizeAlign.size) return vm.setTrap(VmStatus.ERR_WRITE_OOB);

	Memory* srcMem = &vm.memories[src.pointer.kind];
	Allocation* srcAlloc = &srcMem.allocations[src.pointer.index];
	if (!srcAlloc.isReadable) {
		if (!srcAlloc.isPointerValid(src.pointer)) {
			return vm.setTrap(VmStatus.ERR_SRC_ALLOC_FREED);
		}
		return vm.setTrap(VmStatus.ERR_NO_SRC_ALLOC_READ_PERMISSION);
	}

	i64 srcOffset = src.as_s64;
	if (srcOffset < 0) return vm.setTrap(VmStatus.ERR_READ_OOB);
	if (srcOffset + length > srcAlloc.sizeAlign.size) return vm.setTrap(VmStatus.ERR_READ_OOB);

	auto dstFromMem = cast(u32)roundUp(dstAlloc.offset + dstOffset, vm.ptrSize.inBytes);
	auto dstToMem   = max(dstFromMem, cast(u32)roundDown(dstAlloc.offset + dstOffset + length, vm.ptrSize.inBytes));
	PointerId dstFromMemSlot = memOffsetToPtrIndex(dstFromMem, vm.ptrSize);
	PointerId dstToMemSlot   = memOffsetToPtrIndex(dstToMem, vm.ptrSize);
	assert(dstFromMemSlot <= dstToMemSlot);

	auto srcFromMem = cast(u32)roundUp(srcAlloc.offset + srcOffset, vm.ptrSize.inBytes);
	auto srcToMem   = max(srcFromMem, cast(u32)roundDown(srcAlloc.offset + srcOffset + length, vm.ptrSize.inBytes));
	PointerId srcFromMemSlot = memOffsetToPtrIndex(srcFromMem, vm.ptrSize);
	PointerId srcToMemSlot   = memOffsetToPtrIndex(srcToMem, vm.ptrSize);
	assert(srcFromMemSlot <= srcToMemSlot);

	auto dstAlignment = dstOffset % vm.ptrSize.inBytes;
	auto srcAlignment = srcOffset % vm.ptrSize.inBytes;

	// check for unaligned pointer writes
	if (dstAlignment != srcAlignment) {
		auto numPointers = srcMem.countPointerBits(srcFromMemSlot, srcToMemSlot - srcFromMemSlot);
		if (numPointers) {
			// Source contains pointers. Copying them means writing pointers to an unaligned address
			// TODO: Use specialized error for memcopy
			return vm.setTrap(VmStatus.ERR_WRITE_PTR_UNALIGNED);
		}
	}


	scope(exit) vm.ip += 4;

	if (length == 0) {
		return; // noop
	}

	if (dstAlloc == srcAlloc && dstOffset == srcOffset) {
		return; // noop
	}

	if (dstAlloc == srcAlloc && rangesIntersect(dstOffset, srcOffset, length)) {
		// intersection of dst and src
		if (dstOffset < srcOffset) {
			// srcOffset > dstOffset
			//   SSCC
			// XXDD

			// remove dst pointers in XX section
			removePointersInRange(vm, srcMem, dstAlloc, srcToMemSlot, dstToMemSlot);

			// Copy SS over XX (deleting SS pointers)
			size_t* srcPtrBits = cast(size_t*)&srcMem.pointerBitmap.front();
			foreach(size_t srcMemSlot; bitsSetRange(srcPtrBits, srcFromMemSlot, dstToMemSlot)) {
				const sliceSlot = srcMemSlot - srcFromMemSlot;
				const u32 srcMemOffset = ptrIndexToMemOffset(PointerId(cast(u32)srcMemSlot), srcMem.ptrSize);
				const u32 srcAllocOffset = srcMemOffset - srcAlloc.offset;
				AllocId value = vm.pointerRemove(srcMem, srcAlloc, srcAllocOffset);

				const u32 dstMemOffset = ptrIndexToMemOffset(PointerId(cast(u32)(dstFromMemSlot + sliceSlot)), srcMem.ptrSize);
				const u32 dstAllocOffset = dstMemOffset - dstAlloc.offset;
				vm.pointerPut(srcMem, dstAlloc, dstAllocOffset, value);
			}
			// Copy CC over DD (retaining C pointers)
			foreach(size_t srcMemSlot; bitsSetRange(srcPtrBits, dstToMemSlot, srcToMemSlot)) {
				const sliceSlot = srcMemSlot - srcFromMemSlot;
				const u32 srcMemOffset = ptrIndexToMemOffset(PointerId(cast(u32)srcMemSlot), srcMem.ptrSize);
				const u32 srcAllocOffset = srcMemOffset - srcAlloc.offset;
				AllocId value = vm.pointerGet(srcMem, srcAlloc, srcAllocOffset);

				const u32 dstMemOffset = ptrIndexToMemOffset(PointerId(cast(u32)(dstFromMemSlot + sliceSlot)), srcMem.ptrSize);
				const u32 dstAllocOffset = dstMemOffset - dstAlloc.offset;
				vm.pointerPut(srcMem, dstAlloc, dstAllocOffset, value);
			}
		} else {
			// srcOffset < dstOffset
			// SSCC
			//   XXDD

			// remove dst pointers in DD section
			removePointersInRange(vm, srcMem, dstAlloc, srcToMemSlot, dstToMemSlot);

			// Copy CC over DD (deleting CC pointers)
			size_t* srcPtrBits = cast(size_t*)&srcMem.pointerBitmap.front();
			foreach(size_t srcMemSlot; bitsSetRangeReverse(srcPtrBits, dstFromMemSlot, srcToMemSlot)) {
				const sliceSlot = srcMemSlot - srcFromMemSlot;
				const u32 srcMemOffset = ptrIndexToMemOffset(PointerId(cast(u32)srcMemSlot), srcMem.ptrSize);
				const u32 srcAllocOffset = srcMemOffset - srcAlloc.offset;
				AllocId value = vm.pointerRemove(srcMem, srcAlloc, srcAllocOffset);

				const u32 dstMemOffset = ptrIndexToMemOffset(PointerId(cast(u32)(dstFromMemSlot + sliceSlot)), srcMem.ptrSize);
				const u32 dstAllocOffset = dstMemOffset - dstAlloc.offset;
				vm.pointerPut(srcMem, dstAlloc, dstAllocOffset, value);
			}
			// Copy CC over DD (retaining C pointers)
			foreach(size_t srcMemSlot; bitsSetRangeReverse(srcPtrBits, srcFromMemSlot, dstFromMemSlot)) {
				const sliceSlot = srcMemSlot - srcFromMemSlot;
				const u32 srcMemOffset = ptrIndexToMemOffset(PointerId(cast(u32)srcMemSlot), srcMem.ptrSize);
				const u32 srcAllocOffset = srcMemOffset - srcAlloc.offset;
				AllocId value = vm.pointerGet(srcMem, srcAlloc, srcAllocOffset);

				const u32 dstMemOffset = ptrIndexToMemOffset(PointerId(cast(u32)(dstFromMemSlot + sliceSlot)), srcMem.ptrSize);
				const u32 dstAllocOffset = dstMemOffset - dstAlloc.offset;
				vm.pointerPut(srcMem, dstAlloc, dstAllocOffset, value);
			}
		}
	} else {
		// no intersection of dst and src

		// remove dst pointers
		removePointersInRange(vm, dstMem, dstAlloc, dstFromMemSlot, dstToMemSlot);

		// copy outRefs
		size_t* srcPtrBits = cast(size_t*)&srcMem.pointerBitmap.front();
		foreach(size_t srcMemSlot; bitsSetRange(srcPtrBits, srcFromMemSlot, srcToMemSlot)) {
			const sliceSlot = srcMemSlot - srcFromMemSlot;
			const u32 srcMemOffset = ptrIndexToMemOffset(PointerId(cast(u32)srcMemSlot), srcMem.ptrSize);
			const u32 srcAllocOffset = srcMemOffset - srcAlloc.offset;
			AllocId value = vm.pointerGet(srcMem, srcAlloc, srcAllocOffset);

			const u32 dstMemOffset = ptrIndexToMemOffset(PointerId(cast(u32)(dstFromMemSlot + sliceSlot)), srcMem.ptrSize);
			const u32 dstAllocOffset = dstMemOffset - dstAlloc.offset;
			vm.pointerPut(dstMem, dstAlloc, dstAllocOffset, value);
		}
	}

	// copy bytes
	u8* dstBytes = dstMem.memory[].ptr + dstAlloc.offset + dstOffset;
	u8* srcBytes = srcMem.memory[].ptr + srcAlloc.offset + srcOffset;
	memmove(dstBytes, srcBytes, length);

	// copy init bits
	static if (SANITIZE_UNINITIALIZED_MEM) {
		usize* dstInitBits = cast(usize*)&dstMem.initBitmap.front();
		usize* srcInitBits = cast(usize*)&srcMem.initBitmap.front();
		copyBitRange(dstInitBits, srcInitBits, dstAlloc.offset + dstOffset, srcAlloc.offset + srcOffset, length);
	}
}

bool rangesIntersect(usz offsetA, usz offsetB, usz length) {
	if (offsetA > offsetB) {
		return offsetB + length > offsetA;
	} else {
		return offsetA + length > offsetB;
	}
}

// Returns number of pointers removed
u32 removePointersInRange(ref VmState vm, Memory* mem, Allocation* alloc, PointerId from, PointerId to) {
	if (alloc.numOutRefs == 0) return 0 ;
	u32 count;
	size_t* ptr = cast(size_t*)&mem.pointerBitmap.front();
	foreach(size_t slot; bitsSetRange(ptr, from, to)) {
		const u32 memOffset = ptrIndexToMemOffset(PointerId(cast(u32)slot), mem.ptrSize);
		vm.pointerRemove(mem, alloc, memOffset - alloc.offset);
		++count;
	}
	return count;
}
