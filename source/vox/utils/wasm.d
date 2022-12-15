/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module utils.windows.wasi;

version(WebAssembly):

import ldc.attributes;


extern(C):
@nogc nothrow @system:
@llvmAttr("wasm-import-module", "env"):

void writeString(const(char)[] str) @nogc nothrow;
