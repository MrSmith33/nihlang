/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.arch.wasm.memory;

import vox.lib.sys.arch.wasm : wasm_memory_fill, wasm_memory_copy;
public import vox.lib.sys.arch.all.memory : memmove, memcmp;

extern(C) @nogc nothrow @system:

void* memset(void* dest, ubyte val, size_t len) {
	wasm_memory_fill(0, cast(uint)dest, val, len);
	return dest;
}

void* memcpy(void* dest, const void* src, size_t len) {
	wasm_memory_copy(0, cast(uint)dest, cast(uint)src, len);
	return dest;
}
