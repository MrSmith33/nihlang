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
			writefln("%04x ret", addr);
			break;

		case mov:
			u8 dst = code[ip++];
			u8 src = code[ip++];
			writefln("%04x mov r%s, r%s", addr, dst, src);
			break;

		case add_i64:
			u8 dst  = code[ip++];
			u8 src0 = code[ip++];
			u8 src1 = code[ip++];
			writefln("%04x add.i64 r%s, r%s, r%s", addr, dst, src0, src1);
			break;

		case const_s8:
			u8 dst = code[ip++];
			i8 src = code[ip++];
			writefln("%04x const.s8 r%s, %s", addr, dst, src);
			break;

		case load_m8:
		case load_m16:
		case load_m32:
		case load_m64:
			u32 size_bits = (1 << (op - load_m8)) * 8;
			u8 dst = code[ip++];
			i8 src = code[ip++];
			writefln("%04x load.m%s r%s, [r%s]", addr, size_bits, dst, src);
			break;

		case store_m8:
		case store_m16:
		case store_m32:
		case store_m64:
			u32 size_bits = (1 << (op - store_m8)) * 8;
			u8 dst = code[ip++];
			i8 src = code[ip++];
			writefln("%04x store.m%s [r%s], r%s", addr, size_bits, dst, src);
			break;
	}
}
