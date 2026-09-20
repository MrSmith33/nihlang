/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
module vox.tests.context;

import vox.context;
import vox.diagnostic.checker;
import vox.fe.parser;
import vox.fe.source;
import vox.lib;
import vox.tests.infra;

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

	// Testing API
	// -----------

	void compile(string file = __FILE__, int line = __LINE__) {
		auto res = driver.compile();
		if (res.isError) {
			ref diag = driver.context.getError!Diagnostic(res.isError);
			panic(line, file, 1, "Compilation failed, but expected to succeeded");
		}
	}

	DiagnosticChecker compileFail(string file = __FILE__, int line = __LINE__) {
		auto res = driver.compile();
		if (res.isError) {
			ref diag = driver.context.getError!Diagnostic(res.isError);
			return DiagnosticChecker(&driver.context, sink, &diag);
		}
		panic(line, file, 1, "Compilation was expected to fail, but succeeded");
	}

	T* getGlobalPtr(T)(string name) {
		assert(false, "TODO");
		return null;
	}
}
