/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.arch.x64.syscall;

@nogc nothrow @system:

ulong syscall(ulong id) {
	ulong ret;
	asm @nogc nothrow {
		mov RAX, id;
		syscall;
		mov ret, RAX;
	}
	return ret;
}

ulong syscall(ulong id, ulong arg0) {
	ulong ret;
	asm @nogc nothrow {
		mov RAX, id;
		mov RDI, arg0;
		syscall;
		mov ret, RAX;
	}
	return ret;
}

ulong syscall(ulong id, ulong arg0, ulong arg1) {
	ulong ret;
	asm @nogc nothrow {
		mov RAX, id;
		mov RDI, arg0;
		mov RSI, arg1;
		syscall;
		mov ret, RAX;
	}
	return ret;
}

ulong syscall(ulong id, ulong arg0, ulong arg1, ulong arg2) {
	ulong ret;
	asm @nogc nothrow {
		mov RAX, id;
		mov RDI, arg0;
		mov RSI, arg1;
		mov RDX, arg2;
		syscall;
		mov ret, RAX;
	}
	return ret;
}

ulong syscall(ulong id, ulong arg0, ulong arg1, ulong arg2, ulong arg3) {
	ulong ret;
	asm @nogc nothrow {
		mov RAX, id;
		mov RDI, arg0;
		mov RSI, arg1;
		mov RDX, arg2;
		mov R10, arg3;
		syscall;
		mov ret, RAX;
	}
	return ret;
}

ulong syscall(ulong id, ulong arg0, ulong arg1, ulong arg2, ulong arg3, ulong arg4) {
	ulong ret;
	asm @nogc nothrow {
		mov RAX, id;
		mov RDI, arg0;
		mov RSI, arg1;
		mov RDX, arg2;
		mov R10, arg3;
		mov R8, arg4;
		syscall;
		mov ret, RAX;
	}
	return ret;
}

ulong syscall(ulong id, ulong arg0, ulong arg1, ulong arg2, ulong arg3, ulong arg4, ulong arg5) {
	ulong ret;
	asm @nogc nothrow {
		mov RAX, id;
		mov RDI, arg0;
		mov RSI, arg1;
		mov RDX, arg2;
		mov R10, arg3;
		mov R8, arg4;
		mov R9, arg5;
		syscall;
		mov ret, RAX;
	}
	return ret;
}
