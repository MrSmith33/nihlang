/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module fuzzer;

@nogc nothrow:

import vox.vm;
__gshared VmState state;

extern (C) int LLVMFuzzerInitialize(int* argc, char*** argv) {
	import vox.lib;
	vox_init();
	return 0;
}

extern (C) int LLVMFuzzerTestOneInput(const(ubyte*) data, size_t size) {
	assert(false);

	return 0;
}
