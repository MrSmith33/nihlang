/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module utils.windows.posix;

version(Posix) @nogc nothrow @system:

import vox.utils.types;

version(D_InlineAsm_X86_64):

usize syscall(usize syscallId) {
	usize ret;
	asm @nogc nothrow {
		mov RAX, syscallId;
		syscall;
		mov ret, RAX;
	}
	return ret;
}

usize syscall(usize syscallId, usize n) {
	usize ret;
	asm @nogc nothrow {
		mov RAX, syscallId;
		mov RDI, n[RBP];
		syscall;
		mov ret, RAX;
	}
	return ret;
}

usize syscall(usize syscallId, usize n, usize arg1) {
	usize ret;
	asm @nogc nothrow {
		mov RAX, syscallId;
		mov RDI, n[RBP];
		mov RSI, arg1[RBP];
		syscall;
		mov ret, RAX;
	}
	return ret;
}

usize syscall(usize syscallId, usize n, usize arg1, usize arg2) {
	usize ret;
	asm @nogc nothrow {
		mov RAX, syscallId;
		mov RDI, n[RBP];
		mov RSI, arg1[RBP];
		mov RDX, arg2[RBP];
		syscall;
		mov ret, RAX;
	}
	return ret;
}

usize syscall(usize syscallId, usize n, usize arg1, usize arg2, usize arg3) {
	usize ret;
	asm @nogc nothrow {
		mov RAX, syscallId;
		mov RDI, n[RBP];
		mov RSI, arg1[RBP];
		mov RDX, arg2[RBP];
		mov R10, arg3[RBP];
		syscall;
		mov ret, RAX;
	}
	return ret;
}

usize syscall(usize syscallId, usize n, usize arg1, usize arg2, usize arg3, usize arg4) {
	usize ret;
	asm @nogc nothrow {
		mov RAX, syscallId;
		mov RDI, n[RBP];
		mov RSI, arg1[RBP];
		mov RDX, arg2[RBP];
		mov R10, arg3[RBP];
		mov R8, arg4[RBP];
		syscall;
		mov ret, RAX;
	}
	return ret;
}

usize syscall(usize syscallId, usize n, usize arg1, usize arg2, usize arg3, usize arg4, usize arg5) {
	usize ret;
	asm @nogc nothrow {
		mov RAX, syscallId;
		mov RDI, n[RBP];
		mov RSI, arg1[RBP];
		mov RDX, arg2[RBP];
		mov R10, arg3[RBP];
		mov R8, arg4[RBP];
		mov R9, arg5[RBP];
		syscall;
		mov ret, RAX;
	}
	return ret;
}
