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
		if (res.isError) {
			ref diag = driver.context.getError!Diagnostic(res.isError);
			return DiagnosticChecker(&this, &diag);
		}
		panic(line, file, 1, "Compilation was expected to fail, but succeeded");
	}

	T* getGlobalPtr(T)(string name) {
		assert(false, "TODO");
		return null;
	}
}

struct DiagnosticChecker {
	@nogc nothrow:

	// Last command
	enum State {
		init,
		diag,
		anno,
	}

	VoxTestContext* context;
	Diagnostic* diag;
	State state;
	u32 selectedAnnotation;

	DiagnosticChecker expectDiagnostic(string msg = null, string file = __FILE__, int line = __LINE__) {
		if (state != State.init) {
			panic(line, file, 0, "expectDiagnostic must be the first call in a chain");
		}
		if (msg is null) return DiagnosticChecker(context, diag, State.diag);
		if (msg == diag.msg) return DiagnosticChecker(context, diag, State.diag);

		panic(line, file, 0, "Unexpected error message:\n  Expected: %s\n  Got: %s\n", msg, diag.msg);

		return this;
	}

	DiagnosticChecker withAnnotation(string msg = null, string file = __FILE__, int line = __LINE__) {
		if (state != State.diag && state != State.anno) {
			panic(line, file, 0, "expectDiagnostic must be the first call in a chain");
		}

		if (msg is null && diag.annotations.length == 1) {
			// Select annotation zero
			return DiagnosticChecker(context, diag, State.anno, 0);
		}

		if (msg is null) {
			panic(line, file, 0, "Diagnostic has multiple annotations, but message was not specified in a call to withAnnotation");
		}

		foreach(i, ref a; diag.annotations) {
			if (a.msg == msg) {
				return DiagnosticChecker(context, diag, State.anno, cast(u32)i);
			}
		}

		panic(line, file, 0, "Cannot find annotation with message: %s\n", msg);
	}

	DiagnosticChecker pointingAt(string at, string file = __FILE__, int line = __LINE__) {
		if (state != State.anno) {
			panic(line, file, 0, "pointingAt must be called immediately after withAnnotation");
		}

		auto data = context.driver.context.bufs.sources.data;
		auto loc = diag.annotations[selectedAnnotation].location;
		auto slice = data[loc.start.offset..loc.end.offset];

		if (at == slice) return this;

		context.sink.formattedWrite("Annotation is pointing at the wrong location:\n  Expected: %s\n  Got: %s\n", at, slice);
		return this;
	}
}
