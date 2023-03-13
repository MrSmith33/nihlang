/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.error;

import vox.lib;
import vox.vm;

@nogc nothrow:

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

// No new line or dot at the end of the message
void vmFormatError(ref VmState vm, scope SinkDelegate sink) {
	if (vm.status == VmStatus.OK) return;

	u8* code = vm.frameCode;
	u32 firstReg = vm.frameFirstReg;

	final switch(vm.status) with(VmStatus) {
		case OK:
			sink("ok");
			break;

		case ERR_TRAP:
			sink("trap instruction reached");
			break;

		case ERR_COND_OOB:
			sink.formattedWrite("Invalid condition %s, max condition is %s", vm.errData, VmBinCond.max);
			break;

		case ERR_CMP_DIFFERENT_PTR:
			VmReg* dst  = &vm.registers[firstReg + code[vm.frameIp+2]];
			VmReg* src0 = &vm.registers[firstReg + code[vm.frameIp+3]];
			VmReg* src1 = &vm.registers[firstReg + code[vm.frameIp+4]];
			sink.formattedWrite("Cannot compare different pointers\n  r%s: %s\n  r%s: %s\n  r%s: %s",
				code[vm.frameIp+2], *dst,
				code[vm.frameIp+3], *src0,
				code[vm.frameIp+4], *src1);
			break;

		case ERR_CMP_REQUIRES_NO_PTR:
			VmReg* dst  = &vm.registers[firstReg + code[vm.frameIp+2]];
			VmReg* src0 = &vm.registers[firstReg + code[vm.frameIp+3]];
			VmReg* src1 = &vm.registers[firstReg + code[vm.frameIp+4]];
			sink.formattedWrite("Compare operation expects no pointers\n  r%s: %s\n  r%s: %s\n  r%s: %s",
				code[vm.frameIp+2], *dst,
				code[vm.frameIp+3], *src0,
				code[vm.frameIp+4], *src1);
			break;

		case ERR_REGISTER_OOB:
			sink.formattedWrite("Trying to access register out of bounds of register stack.\n  Num frame vm.registers: %s\n  Invalid register: r%s",
				vm.registers.length - firstReg, vm.errData - firstReg);
			break;

		case ERR_PTR_SRC1:
			VmReg* dst  = &vm.registers[firstReg + code[vm.frameIp+1]];
			VmReg* src0 = &vm.registers[firstReg + code[vm.frameIp+2]];
			VmReg* src1 = &vm.registers[firstReg + code[vm.frameIp+3]];

			sink.formattedWrite("add.i64 can only contain pointers in the first argument.\n  r%s: %s\n  r%s: %s\n  r%s: %s",
				code[vm.frameIp+1], *dst,
				code[vm.frameIp+2], *src0,
				code[vm.frameIp+3], *src1);
			break;

		case ERR_STORE_NO_WRITE_PERMISSION:
			VmReg* dst = &vm.registers[firstReg + code[vm.frameIp+1]];
			VmReg* src = &vm.registers[firstReg + code[vm.frameIp+2]];

			sink.formattedWrite("Writing to %s pointer is disabled.\n  r%s: %s\n  r%s: %s",
				memoryKindString[dst.pointer.kind],
				code[vm.frameIp+1], *dst,
				code[vm.frameIp+2], *src);
			break;

		case ERR_LOAD_NO_READ_PERMISSION:
			VmReg* dst = &vm.registers[firstReg + code[vm.frameIp+1]];
			VmReg* src = &vm.registers[firstReg + code[vm.frameIp+2]];

			sink.formattedWrite("Reading from %s pointer is disabled.\n  r%s: %s\n  r%s: %s",
				memoryKindString[src.pointer.kind],
				code[vm.frameIp+1], *dst,
				code[vm.frameIp+2], *src);
			break;

		case ERR_STORE_NOT_PTR:
			VmReg* dst = &vm.registers[firstReg + code[vm.frameIp+1]];

			sink.formattedWrite("Writing to non-pointer value (r%s:%s)", code[vm.frameIp+1], *dst);
			break;

		case ERR_LOAD_NOT_PTR:
			VmReg* src = &vm.registers[firstReg + code[vm.frameIp+2]];
			sink.formattedWrite("Reading from non-pointer value (r%s:%s)", code[vm.frameIp+2], *src);
			break;

		case ERR_LOAD_INVALID_POINTER:
			VmReg* src = &vm.registers[firstReg + code[vm.frameIp+2]];
			sink.formattedWrite("Reading from invalid pointer (r%s:%s)", code[vm.frameIp+2], *src);
			break;

		case ERR_STORE_OOB:
			u8 op = code[vm.frameIp+0];
			u32 size = 1 << (op - VmOpcode.store_m8);
			VmReg* dst = &vm.registers[firstReg + code[vm.frameIp+1]];
			Memory* mem = &vm.memories[dst.pointer.kind];
			Allocation* alloc = &mem.allocations[dst.pointer.index];

			i64 offset = dst.as_s64;

			sink.formattedWrite("Writing outside of the allocation %s\nWriting %s bytes at offset %s, to allocation of %s bytes",
				dst.pointer,
				size,
				offset,
				alloc.size);
			break;

		case ERR_STORE_PTR_UNALIGNED:
			u8 op = code[vm.frameIp+0];
			u32 size = 1 << (op - VmOpcode.store_m8);
			VmReg* dst = &vm.registers[firstReg + code[vm.frameIp+1]];
			Memory* mem = &vm.memories[dst.pointer.kind];
			Allocation* alloc = &mem.allocations[dst.pointer.index];

			u64 offset = dst.as_u64;

			sink.formattedWrite("Writing pointer value (r%s:%s) to an unaligned offset (0x%X)",
				code[vm.frameIp+1], *dst,
				offset);
			break;

		case ERR_LOAD_OOB:
			u8 op = code[vm.frameIp+0];
			u32 size = 1 << (op - VmOpcode.load_m8);
			VmReg* src = &vm.registers[firstReg + code[vm.frameIp+2]];
			Memory* mem = &vm.memories[src.pointer.kind];
			Allocation* alloc = &mem.allocations[src.pointer.index];

			i64 offset = src.as_s64;

			sink.formattedWrite("Reading outside of the allocation %s\nReading %s bytes at offset %s, from allocation of %s bytes",
				src.pointer,
				size,
				offset,
				alloc.size);
			break;

		case ERR_LOAD_UNINIT:
			u8 op = code[vm.frameIp+0];
			u32 size = 1 << (op - VmOpcode.load_m8);
			VmReg* src = &vm.registers[firstReg + code[vm.frameIp+2]];
			Memory* mem = &vm.memories[src.pointer.kind];
			Allocation* alloc = &mem.allocations[src.pointer.index];

			u64 offset = src.as_u64;

			sink.formattedWrite("Reading uninitialized memory from allocation (r%s:%s)\n  Reading %s bytes at offset %s",
				code[vm.frameIp+2], *src,
				size,
				offset);

			vm.printMem(sink, src.pointer, cast(u32)offset, size, 16, 2);
			break;
	}
}