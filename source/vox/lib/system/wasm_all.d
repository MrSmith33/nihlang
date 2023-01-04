/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

/// This is for all versions of WebAssembly, without or without WASI
module vox.lib.system.wasm_all;

version(WebAssembly) @nogc nothrow @system:

pragma(LDC_intrinsic, "llvm.wasm.memory.grow.i32")
/// mem: 0
/// pageIncrease: The number of WebAssembly pages you want to grow the memory by (each one is 64KiB in size).
/// Returns: The previous size of the memory, in units of WebAssembly pages, or -1 on fail.
/// The memory.grow instruction is non-deterministic. It may either succeed, returning the old memory size,
/// or fail, returning -1. Failure must occur if the referenced memory instance has a maximum size
/// defined that would be exceeded. However, failure can occur in other cases as well. In practice,
/// the choice depends on the resources available to the embedder.
/// https://webassembly.github.io/spec/core/exec/instructions.html#exec-memory-grow
int wasm_memory_grow(int mem, int pageIncrease);

pragma(LDC_intrinsic, "llvm.wasm.memory.size.i32")
/// mem: 0
/// Returns the current size of memory.
/// https://webassembly.github.io/spec/core/exec/instructions.html#exec-memory-size
int wasm_memory_size(int mem);

pragma(LDC_intrinsic, "llvm.wasm.memory.fill.i32")
int wasm_memory_fill(int mem, int dst, int val, int size);

extern(C) void* memset(void* dest, ubyte val, size_t len) {
	//import ldc.intrinsics : llvm_memset;
	//llvm_memset!size_t(dest, val, len);
	//for(size_t i = 0; i < len; ++i) (cast(ubyte*)dest)[i] = val;
	wasm_memory_fill(0, cast(uint)dest, val, len);
	return dest;
}

pragma(LDC_intrinsic, "llvm.wasm.memory.copy.i32")
int wasm_memory_copy(int mem, int dst, int src, int size);

extern(C) void* memcpy(void* dest, const void* src, size_t len) {
	//import ldc.intrinsics : llvm_memcpy;
	//llvm_memcpy!size_t(dest, src, len);
	//for(size_t i = 0; i < len; ++i) (cast(ubyte*)dest)[i] = (cast(ubyte*)src)[i];
	wasm_memory_copy(0, cast(uint)dest, cast(uint)src, len);
	return dest;
}
