/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.error;

import vox.lib;
import vox.vm;

@nogc nothrow:

enum VmStatus : u8 {
	RUNNING,
	FINISHED,

	ERR_BUDGET,
	ERR_TRAP,
	ERR_COND_OOB,
	ERR_CMP_DIFFERENT_PTR,
	ERR_CMP_REQUIRES_NO_PTR,
	ERR_PTR_SRC1,

	ERR_WRITE_PTR_UNALIGNED,
	ERR_LEN_IS_PTR,
	ERR_SRC_NOT_PTR,
	ERR_DST_NOT_PTR,
	ERR_READ_UNINIT,
	ERR_READ_OOB,
	ERR_WRITE_OOB,
	ERR_NO_SRC_MEM_READ_PERMISSION,
	ERR_NO_DST_MEM_WRITE_PERMISSION,
	ERR_NO_SRC_ALLOC_READ_PERMISSION,
	ERR_NO_DST_ALLOC_WRITE_PERMISSION,
	ERR_SRC_ALLOC_FREED,
	ERR_DST_ALLOC_FREED,

	ERR_CALL_INSUFFICIENT_STACK_ARGS,
	ERR_CALL_INVALID_STACK_ARG_SIZES,

	ERR_ESCAPED_PTR_TO_STACK_IN_REG,
	ERR_ESCAPED_PTR_TO_STACK_IN_MEM,
}

bool isError(VmStatus status) { return status > VmStatus.FINISHED; }

// No new line or dot at the end of the message
void vmFormatError(ref VmState vm, scope SinkDelegate sink) {
	final switch(vm.status) with(VmStatus) {
		case RUNNING:
			sink("Running");
			break;

		case FINISHED:
			sink("Finished");
			break;

		case ERR_BUDGET:
			sink("Execution budget exceeded");
			break;

		case ERR_TRAP:
			sink("Trap instruction reached");
			break;

		case ERR_COND_OOB:
			sink.formattedWrite("Invalid condition %s, max condition is %s", vm.errData, VmBinCond.max);
			break;

		case ERR_CMP_DIFFERENT_PTR:
			VmReg* dst  = &vm.regs[vm.code[vm.ip+2]];
			VmReg* src0 = &vm.regs[vm.code[vm.ip+3]];
			VmReg* src1 = &vm.regs[vm.code[vm.ip+4]];
			sink.formattedWrite("Compared pointers must point to the same allocation\n  dst: r%s = %s\n  lhs: r%s = %s\n  rhs: r%s = %s",
				vm.code[vm.ip+2], *dst,
				vm.code[vm.ip+3], *src0,
				vm.code[vm.ip+4], *src1);
			break;

		case ERR_CMP_REQUIRES_NO_PTR:
			VmReg* dst  = &vm.regs[vm.code[vm.ip+2]];
			VmReg* src0 = &vm.regs[vm.code[vm.ip+3]];
			VmReg* src1 = &vm.regs[vm.code[vm.ip+4]];
			sink.formattedWrite("Compare operation expects non-pointers\n  dst: r%s = %s\n  lhs: r%s = %s\n  rhs: r%s = %s",
				vm.code[vm.ip+2], *dst,
				vm.code[vm.ip+3], *src0,
				vm.code[vm.ip+4], *src1);
			break;

		case ERR_PTR_SRC1:
			VmReg* dst  = &vm.regs[vm.code[vm.ip+1]];
			VmReg* src0 = &vm.regs[vm.code[vm.ip+2]];
			VmReg* src1 = &vm.regs[vm.code[vm.ip+3]];

			sink.formattedWrite("add.i64 only allows pointers in the first argument.\n  dst: r%s = %s\n  lhs: r%s = %s\n  rhs: r%s = %s",
				vm.code[vm.ip+1], *dst,
				vm.code[vm.ip+2], *src0,
				vm.code[vm.ip+3], *src1);
			break;

		case ERR_NO_DST_MEM_WRITE_PERMISSION:
			VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
			VmReg* src = &vm.regs[vm.code[vm.ip+2]];

			sink.formattedWrite("Writing to %s pointer is disabled.\n  dst: r%s = %s\n  src: r%s = %s",
				memoryKindString[dst.pointer.kind],
				vm.code[vm.ip+1], *dst,
				vm.code[vm.ip+2], *src);
			break;

		case ERR_DST_NOT_PTR:
			VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
			sink.formattedWrite("Destination is not a pointer\n  dst: r%s = %s", vm.code[vm.ip+1], *dst);
			break;

		case ERR_READ_OOB:
			u8 op = vm.code[vm.ip+0];
			u32 size = 1 << (op - VmOpcode.load_m8);
			VmReg* src = &vm.regs[vm.code[vm.ip+2]];
			Memory* mem = &vm.memories[src.pointer.kind];
			Allocation* alloc = &mem.allocations[src.pointer.index];

			i64 offset = src.as_s64;

			sink.formattedWrite("Reading outside of the allocation\n  allocation: %s\n  allocation size: %s bytes\n  read size: %s bytes\n  read offset: %s bytes",
				src.pointer,
				alloc.sizeAlign.size,
				size,
				offset);
			break;

		case ERR_WRITE_OOB:
			u8 op = vm.code[vm.ip+0];
			u32 size = 1 << (op - VmOpcode.store_m8);
			VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
			Memory* mem = &vm.memories[dst.pointer.kind];
			Allocation* alloc = &mem.allocations[dst.pointer.index];

			i64 offset = dst.as_s64;

			sink.formattedWrite("Writing outside of the allocation\n  allocation: %s\n  allocation size: %s bytes\n  write size: %s bytes\n  write offset: %s bytes",
				dst.pointer,
				alloc.sizeAlign.size,
				size,
				offset);
			break;

		case ERR_WRITE_PTR_UNALIGNED:
			u8 op = vm.code[vm.ip+0];
			u32 size = 1 << (op - VmOpcode.store_m8);
			VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
			Memory* mem = &vm.memories[dst.pointer.kind];
			Allocation* alloc = &mem.allocations[dst.pointer.index];

			u64 offset = dst.as_u64;

			sink.formattedWrite("Writing pointer value to an unaligned offset\n  dst: r%s = %s\n  offset: %s bytes\n  expected alignment: %s bytes",
				vm.code[vm.ip+1], *dst, offset, vm.ptrSize.inBytes);
			break;

		case ERR_DST_ALLOC_FREED:
			VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
			sink.formattedWrite("Writing to freed allocation\n  dst: r%s = %s", vm.code[vm.ip+1], *dst);
			break;


		case ERR_NO_SRC_MEM_READ_PERMISSION:
			VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
			VmReg* src = &vm.regs[vm.code[vm.ip+2]];

			sink.formattedWrite("Reading from %s pointer is disabled.\n  dst: r%s = %s\n  src: r%s = %s",
				memoryKindString[src.pointer.kind],
				vm.code[vm.ip+1], *dst,
				vm.code[vm.ip+2], *src);
			break;

		case ERR_SRC_NOT_PTR:
			VmReg* src = &vm.regs[vm.code[vm.ip+2]];
			sink.formattedWrite("Source is not a pointer\n  src: r%s = %s", vm.code[vm.ip+2], *src);
			break;

		case ERR_READ_UNINIT:
			u8 op = vm.code[vm.ip+0];
			u32 size = 1 << (op - VmOpcode.load_m8);
			VmReg* src = &vm.regs[vm.code[vm.ip+2]];
			Memory* mem = &vm.memories[src.pointer.kind];
			Allocation* alloc = &mem.allocations[src.pointer.index];

			u64 offset = src.as_u64;

			sink.formattedWrite("Reading from uninitialized memory\n  allocation: r%s = %s\n  size: %s bytes\n  offset: %s bytes\n",
				vm.code[vm.ip+2], *src,
				size,
				offset);

			vm.printMem(sink, src.pointer, cast(u32)offset, size, 16, 2);
			break;

		case ERR_SRC_ALLOC_FREED:
			VmReg* src = &vm.regs[vm.code[vm.ip+2]];
			sink.formattedWrite("Reading from freed allocation\n  src: r%s = %s", vm.code[vm.ip+2], *src);
			break;

		case ERR_NO_DST_ALLOC_WRITE_PERMISSION:
			VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
			VmReg* src = &vm.regs[vm.code[vm.ip+2]];
			sink.formattedWrite("Destination allocation has no write permission\n  dst: r%s = %s\n  src: r%s = %s",
				vm.code[vm.ip+1], *dst, vm.code[vm.ip+2], *src);
			break;

		case ERR_NO_SRC_ALLOC_READ_PERMISSION:
			VmReg* dst = &vm.regs[vm.code[vm.ip+1]];
			VmReg* src = &vm.regs[vm.code[vm.ip+2]];
			sink.formattedWrite("Source allocation has no read permission\n  dst: r%s = %s\n  src: r%s = %s",
				vm.code[vm.ip+1], *dst, vm.code[vm.ip+2], *src);
			break;

		case ERR_LEN_IS_PTR:
			VmReg* len = &vm.regs[vm.code[vm.ip+3]];
			sink.formattedWrite("Length parameter must be a non-pointer\n  length r%s = %s", vm.code[vm.ip+3], *len);
			break;


		case ERR_CALL_INSUFFICIENT_STACK_ARGS:
			u8 numStackParams = cast(u8)vm.errData;
			sink.formattedWrite("Insufficient stack slots on the caller stack\nCallee stack parameters: %s\nCaller frame stack allocations: %s",
				numStackParams,
				vm.numFrameStackSlots);
			break;

		case ERR_CALL_INVALID_STACK_ARG_SIZES:
			FuncId calleeId = *cast(FuncId*)&vm.code[vm.ip+3];
			VmFunction* callee = &vm.functions[calleeId];
			SizeAndAlign* slotSizes = &callee.stackSlotSizes.front();
			u8 numStackParams = callee.numStackParams;

			sink("Invalid stack slots sizes of stack arguments on the caller stack");
			foreach(i; 0..numStackParams) {
				if (slotSizes[i] != vm.stackSlots[i].sizeAlign) {
					sink.formattedWrite("\n  arg %s: arg size %s != parameter size %s",
						i,
						slotSizes[i],
						vm.stackSlots[i].sizeAlign);
				}
			}
			break;


		case ERR_ESCAPED_PTR_TO_STACK_IN_REG:
			u8 regIndex = cast(u8)vm.errData;
			VmReg* reg = &vm.regs[regIndex];
			sink.formattedWrite(
				"Address of stack slot %s escapes through register r%s",
				*reg, regIndex);
			break;

		case ERR_ESCAPED_PTR_TO_STACK_IN_MEM:
			u8 slotIndex = cast(u8)vm.errData;
			auto slotId = AllocId(vm.frameFirstStackSlot + slotIndex, MemoryKind.stack_mem);
			sink.formattedWrite(
				"Address of stack slot %s escapes through memory",
				slotId);
			break;
	}
}
