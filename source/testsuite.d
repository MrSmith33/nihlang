/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module testsuite;

@nogc nothrow:

import nih.all;
import vox.lib.types;

pragma(mangle, "vox_main")
i32 vox_main(string[] args)
{
	import vox.lib.thread : threads_supported;
	static if (threads_supported) {
		import vox.lib.tests.atomic;
		vox.lib.tests.atomic.runTests();
	}

	VoxAllocator allocator;

	import vox.vm.tests.tests;
	runVmTests(allocator);

	import vox.tests.tests;
	runVoxTests(allocator);

	// import vox.lib.bitcopy_test;
	// test_copyBitRange;
	//testFormatting;
	//testDemangler;
	//testStackTrace;
	//panic("Test panic message %s", 42);
	return 0;
}
