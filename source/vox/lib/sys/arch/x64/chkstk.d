/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.arch.x64.chkstk;

//import ldc.llvmasm;
//import ldc.attributes;

// https://github.com/skeeto/w64devkit/blob/master/src/libchkstk.S
version(NO_DEPS) export extern(C) void __chkstk() {
	asm {
		naked;
		push RAX;
		push RCX;
		mov  RCX, qword ptr GS:[16]; // rcx = stack low address
		neg  RAX;                    // rax = frame low address
		add  RAX, RSP;               //
		jb   L0;                     // frame low address overflow?
		xor  EAX, EAX;               // overflowed: frame low address = null
	L0:
		sub  RCX, 4096;              // extend stack into guard page
		test dword ptr [RCX], EAX;   // commit page (two instruction bytes)
	L1:
		cmp  RCX, RAX;
		ja   L1;
		pop  RCX;
		pop  RAX;
		ret;
	};
}
