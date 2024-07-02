/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

module vox.lib.sys.os.unknown;

version(WebAssembly) public import vox.lib.sys.os.unknown.api.wasm;
