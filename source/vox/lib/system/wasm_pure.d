/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

/// This is for pure WebAssembly, without WASI
module vox.lib.system.wasm_pure;

version(WebAssembly) @nogc nothrow @system:

import ldc.attributes : llvmAttr;

extern(C) @llvmAttr("wasm-import-module", "env"):


void writeString(const(char)[] str);
