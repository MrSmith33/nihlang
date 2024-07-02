/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

/// This is API for pure WebAssembly, without WASI
/// Host must define functions specified below
module vox.lib.sys.os.unknown.api.wasm;

@nogc nothrow @system:

import ldc.attributes : llvmAttr;

extern(C) @llvmAttr("wasm-import-module", "env"):


void writeString(const(char)[] str);
long getTimeNs();
