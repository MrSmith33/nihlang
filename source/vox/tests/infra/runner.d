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
	if (suite.isFilterEnabled) {
		writefln("Selected %s of %s tests to run", suite.numTestsToRun, suite.instances.length);
	} else {
		writefln("Running all %s tests", suite.numTestsToRun);
	}

	MonoTime start = currTime;
	foreach(ref test; suite.instances) {
		if (!suite.isFilterEnabled || test.onlyThis) {
			auto context = suite.contexts[test.contextIndex];
			context.runTest(test);
		}
	}
	MonoTime end = currTime;
	writefln("Done %s tests in %s", suite.numTestsToRun, end - start);

	return 0;
}
