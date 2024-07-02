/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

/// This is for all versions of WebAssembly, without or without WASI
module vox.lib.sys.arch.wasm;

import vox.lib.types;

@nogc nothrow @system:

enum WASM_PAGE = 64 * 1024;

/// mem: 0
/// pageIncrease: The number of WebAssembly pages you want to grow the memory by (each one is 64KiB in size).
/// Returns: The previous size of the memory, in units of WebAssembly pages, or -1 on fail.
/// The memory.grow instruction is non-deterministic. It may either succeed, returning the old memory size,
/// or fail, returning -1. Failure must occur if the referenced memory instance has a maximum size
/// defined that would be exceeded. However, failure can occur in other cases as well. In practice,
/// the choice depends on the resources available to the embedder.
/// https://webassembly.github.io/spec/core/exec/instructions.html#exec-memory-grow
// Shared memories are not growable past the max size.
// --max-memory=<size> needs to be used
// --shared-memory linker flag
pragma(LDC_intrinsic, "llvm.wasm.memory.grow.i32")
i32 wasm_memory_grow(i32 mem, i32 pageIncrease);

pragma(LDC_intrinsic, "llvm.wasm.memory.size.i32")
/// mem: 0
/// Returns the current size of memory.
/// https://webassembly.github.io/spec/core/exec/instructions.html#exec-memory-size
i32 wasm_memory_size(i32 mem);

pragma(LDC_intrinsic, "llvm.wasm.memory.fill.i32")
i32 wasm_memory_fill(i32 mem, i32 dst, i32 val, i32 size);

pragma(LDC_intrinsic, "llvm.wasm.memory.copy.i32")
i32 wasm_memory_copy(i32 mem, i32 dst, i32 src, i32 size);

// https://webassembly.github.io/threads/core/syntax/instructions.html#syntax-instr-atomic-memory
pragma(LDC_intrinsic, "llvm.wasm.memory.atomic.notify")
u32 wasm_memory_atomic_notify(u32* ptr, u32 waiters);

// when timeout_ns is -1 - it is infinite
pragma(LDC_intrinsic, "llvm.wasm.memory.atomic.wait32")
u32 wasm_memory_atomic_wait32(u32* ptr, u32 expression, i64 timeout_ns);

pragma(LDC_intrinsic, "llvm.wasm.memory.atomic.wait64")
u32 wasm_memory_atomic_wait64(u64* ptr, u64 expression, i64 timeout_ns);
