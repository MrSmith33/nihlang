/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.tests.tests;

import vox.lib;
import vox.tests.infra;
import vox.tests.context;

@nogc nothrow:

i32 runVoxTests(ref VoxAllocator allocator) {
	auto context = VoxTestContext(&allocator, stdoutSink);
	TestSuite suite;
	collectTests!(vox.tests.tests)(allocator, suite);
	return runTests(context.toInterface, suite);
}
