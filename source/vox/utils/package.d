/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.utils;

public import vox.utils.entrypoint;
public import vox.utils.error;
public import vox.utils.format;
public import vox.utils.log;
public import vox.utils.stacktrace;
public import vox.utils.types;
     version(Windows)     public import vox.utils.windows;
else version(linux)       public import vox.utils.linux;
else version(OSX)         public import vox.utils.macos;
// WASI must be checked before WebAssembly, because WASI is defined together with WebAssembly
else version(WASI)        public import vox.utils.wasi;
else version(WebAssembly) public import vox.utils.wasm;
version(Posix)            public import vox.utils.posix;

enum u32 stdin  = 0;
enum u32 stdout = 1;
enum u32 stderr = 2;

T min(T)(T a, T b) {
	if (a < b) return a;
	return b;
}

T max(T)(T a, T b) {
	if (a > b) return a;
	return b;
}

const(char)[] fromStringz(const(char)* cString) @nogc nothrow {
	if (cString == null) return null;
	const(char)* cursor = cString;
	while(*cursor) ++cursor;
	usize length = cast(usize)(cursor - cString);
	return cString[0..length];
}

version(Windows)
noreturn vox_exit_process(u32 exitCode) @nogc nothrow {
	ExitProcess(exitCode);
}

version(WebAssembly) {
	import ldc.intrinsics;

	pragma(LDC_intrinsic, "llvm.trap")
	noreturn vox_llvm_trap() @nogc nothrow;

	version(WASI) {
		noreturn vox_exit_process(u32 exitCode) @nogc nothrow {
			proc_exit(exitCode);
		}
	} else {
		noreturn vox_exit_process(u32 exitCode) @nogc nothrow {
			vox_llvm_trap();
		}
	}

	extern(C) void* memcpy(void* dest, const void* src, usize len) {
		llvm_memcpy!usize(dest, src, len);
		return dest;
	}

	extern(C) void* memset(void* dest, ubyte val, usize len) {
		llvm_memset!usize(dest, val, len);
		return dest;
	}
}
