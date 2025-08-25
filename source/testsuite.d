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
	import vox.tests.infra;

	VoxAllocator allocator;
	TestSuite suite;

	// Contexts need to be live during runTests call
	auto context0 = SimpleTestContext(&allocator, stdoutSink);
	import vox.vm.tests.context;
	auto context1 = VmTestContext(&allocator, stdoutSink);
	import vox.tests.context;
	auto context2 = VoxTestContext(&allocator, stdoutSink);

	import vox.lib.thread : threads_supported;
	static if (threads_supported) {{
		import vox.lib.tests.atomic;
		auto contextIndex = suite.registerContext(allocator, context0.toInterface);
		collectTestDefinitions!(vox.lib.tests.atomic)(allocator, suite, contextIndex);
	}}

	{
		import vox.vm.tests.tests;
		auto contextIndex = suite.registerContext(allocator, context1.toInterface);
		collectTestDefinitions!(vox.vm.tests.tests)(allocator, suite, contextIndex);
	}

	{
		import vox.tests.tests;
		auto contextIndex = suite.registerContext(allocator, context2.toInterface);
		collectTestDefinitions!(vox.tests.tests)(allocator, suite, contextIndex);
	}

	instantiateTests(allocator, suite);
	runTests(suite);

	// import vox.lib.bitcopy_test;
	// test_copyBitRange;
	//testFormatting;
	//testDemangler;
	//testStackTrace;
	//panic("Test panic message %s", 42);
	return 0;
}
