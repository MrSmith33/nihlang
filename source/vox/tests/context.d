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

	// Testing API
	// -----------

	DiagnosticChecker compileFail(string file = __FILE__, int line = __LINE__) {
		auto res = driver.compile();
		if (res.isError) return DiagnosticChecker(&this, res.isError);
		panic(line, file, 1, "Compilation was expected to fail, but succeeded");
	}

	T* getGlobalPtr(T)(string name) {
		assert(false, "TODO");
		return null;
	}
}

struct DiagnosticChecker {
	@nogc nothrow:

	VoxTestContext* context;
	u32 errorIndex;

	DiagnosticChecker expectDiagnostic(string msg = null, string file = __FILE__, int line = __LINE__) {
		ref diag = context.driver.context.getError!Diagnostic(errorIndex);

		if (msg is null) return this;
		if (msg == diag.msg) return this;

		context.sink.formattedWrite("Unexpected error message:\n  Expected: %s\n  Got: %s\n", msg, diag.msg);

		return this;
	}
}
