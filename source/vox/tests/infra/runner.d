/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Test runner
module vox.tests.infra.runner;

import vox.lib;
import vox.types;
import vox.tests.infra;
import vox.tests.tests;

@nogc nothrow:

i32 runTests(ref TestSuite suite) {
	u32 numTests;
	if (suite.filter.enabled) {
		foreach(ref test; suite.tests) {
			if (suite.filter.shouldRun(test)) {
				++numTests;
			}
		}

		writefln("Selected %s of %s tests to run", numTests, suite.tests.length);
	} else {
		numTests = cast(u32)suite.tests.length;
		writefln("Running %s tests", suite.tests.length);
	}

	// Warmup (first run does all the allocations and memory faults)
	//if (suite.filter.disabled && suite.tests.length) {
	//	context.runTest(suite.tests[0]);
	//	context.runTest(suite.tests[0]);
	//	context.runTest(suite.tests[0]);
	//}
	// End warmup

	MonoTime start = currTime;
	foreach(ref test; suite.tests) {
		auto context = suite.contexts[test.contextIndex];
		context.runTest(test);
	}
	MonoTime end = currTime;
	writefln("Done %s tests in %s", suite.tests.length, end - start);

	return 0;
}
