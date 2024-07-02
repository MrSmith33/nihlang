/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.memory;

version(VANILLA_D) {
	public import core.stdc.string : memmove;
}

version(NO_DEPS) {
	version(WebAssembly) public import vox.lib.sys.arch.wasm.memory;
	else public import vox.lib.sys.arch.all.memory;
}
