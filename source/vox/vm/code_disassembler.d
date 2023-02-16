/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.code_disassembler;

import vox.lib;
import vox.vm.opcode;

@nogc nothrow:

void disasm(scope SinkDelegate sink, u8[] code, u32 offset = 0) {
	u32 ip;
	while(ip < code.length) {
		disasmOne(sink, code, ip, offset);
	}
}

void disasmOne(scope SinkDelegate sink, u8[] code, ref u32 ip, u32 offset = 0) {
	auto addr = ip + offset;
	VmOpcode op = cast(VmOpcode)code[ip++];
	final switch(op) with(VmOpcode) {
		case ret:
			writefln("%04X ret", addr);
			break;

		case trap:
			writefln("%04X trap", addr);
			break;

		case jump:
			i32 jump_offset = *cast(i32*)&code[ip];
			ip += 4;
			writefln("%04X jump %04X", addr, addr + jump_offset + 5);
			break;

		case branch:
			u8 src = code[ip++];
			i32 jump_offset = *cast(i32*)&code[ip];
			ip += 4;
			writefln("%04X branch r%s %04X", addr, src, addr + jump_offset + 6);
			break;

		case push:
			u8 length = code[ip++];
			writefln("%04X push %s", addr, length);
			break;

		case pop:
			u8 length = code[ip++];
			writefln("%04X pop %s", addr, length);
			break;

		case call:
			i32 func_id = *cast(i32*)&code[ip];
			ip += 4;
			writefln("%04X call f%s", addr, func_id);
			break;

		case mov:
			u8 dst = code[ip++];
			u8 src = code[ip++];
			writefln("%04X mov r%s, r%s", addr, dst, src);
			break;

		case cmp:
			u8 cond = code[ip++];
			u8 dst  = code[ip++];
			u8 src0 = code[ip++];
			u8 src1 = code[ip++];
			if (cond <= VmBinCond.max)
				writefln("%04X cmp.%s r%s, r%s, r%s", addr, vmBinCondString[cond], dst, src0, src1);
			else
				writefln("%04X cmp.%s r%s, r%s, r%s", addr, cond, dst, src0, src1);
			break;

		case add_i64:
			u8 dst  = code[ip++];
			u8 src0 = code[ip++];
			u8 src1 = code[ip++];
			writefln("%04X add.i64 r%s, r%s, r%s", addr, dst, src0, src1);
			break;

		case sub_i64:
			u8 dst  = code[ip++];
			u8 src0 = code[ip++];
			u8 src1 = code[ip++];
			writefln("%04X sub.i64 r%s, r%s, r%s", addr, dst, src0, src1);
			break;

		case const_s8:
			u8 dst = code[ip++];
			i8 src = code[ip++];
			writefln("%04X const.s8 r%s, %s", addr, dst, src);
			break;

		case load_m8:
		case load_m16:
		case load_m32:
		case load_m64:
			u32 size_bits = (1 << (op - load_m8)) * 8;
			u8 dst = code[ip++];
			i8 src = code[ip++];
			writefln("%04X load.m%s r%s, [r%s]", addr, size_bits, dst, src);
			break;

		case store_m8:
		case store_m16:
		case store_m32:
		case store_m64:
			u32 size_bits = (1 << (op - store_m8)) * 8;
			u8 dst = code[ip++];
			i8 src = code[ip++];
			writefln("%04X store.m%s [r%s], r%s", addr, size_bits, dst, src);
			break;
	}
}
