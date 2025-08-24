/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.tests.context;

import vox.lib;
import vox.tests.infra;

struct VoxTestContext {
	mixin TestContextUtils;

	@nogc nothrow:

	SinkDelegate sink;
	TestInstance test;

	this(VoxAllocator* allocator, SinkDelegate _sink) {
		sink = _sink;
	}

	void runTest(ref TestInstance test) {
		test.test_handler(&this);
	}
}
