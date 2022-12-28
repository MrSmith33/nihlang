/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.utils;

public import vox.utils.error;
public import vox.utils.format;
public import vox.utils.types;
public import vox.utils.system.entrypoint;
public import vox.utils.system.stacktrace;
     version(Windows)     public import vox.utils.system.windows;
else version(linux)       public import vox.utils.system.linux;
else version(OSX)         public import vox.utils.system.macos;
// WASI must be checked before WebAssembly, because WASI is defined together with WebAssembly
else version(WASI)        public import vox.utils.system.wasi;
else version(WebAssembly) public import vox.utils.system.wasm;

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
