/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
module vox.tests.context;

import vox.lib;
import vox.tests.infra;
import vox.fe.source;
import vox.fe.parser;
import vox.context;

struct VoxTestContext {
	mixin TestContextUtils;

	@nogc nothrow:

	Allocator* allocator;
	SinkDelegate sink;
	TestInstance test;
	Driver driver;

	this(Allocator* allocator, SinkDelegate _sink) {
		this.allocator = allocator;
		sink = _sink;
	}

	void init() {
		assert(!driver.init(*allocator).isError);
	}

	void runTest(ref TestInstance _test) {
		test = _test;
		driver.startCompilation();
		driver.addHar("test.har", test.source.asciiStripLeft);
		test.test_handler(&this);
	}

	T* getGlobalPtr(T)(string name) {
		assert(false, "TODO");
		return null;
	}
}
