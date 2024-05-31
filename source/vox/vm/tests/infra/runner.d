/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Test runner
module vox.vm.tests.infra.runner;

import vox.lib;
import vox.vm;
import vox.vm.tests.infra;
import vox.vm.tests.tests;

@nogc nothrow:

i32 runVmTests() {
	VoxAllocator allocator;
	auto context = VmTestContext(&allocator, stdoutSink);

	TestSuite suite;
	vox.vm.tests.tests.vmTests(allocator, suite);

	if (suite.filter.enabled) {
		u32 numTests;
		writefln("Running %s tests with filter", suite.tests.length);
		MonoTime start = currTime;
		foreach(ref test; suite.tests) {
			if (suite.filter.shouldRun(test)) {
				++numTests;
				runSingleTest(context, test);
			}
		}
		MonoTime end = currTime;
		writefln("Done %s/%s tests in %s", numTests, suite.tests.length, end - start);
		return 0;
	}

	writefln("Running %s tests", suite.tests.length);

	// Warmup (first run does all the allocations and memory faults)
	if (suite.tests.length) {
		runSingleTest(context, suite.tests[0]);
		runSingleTest(context, suite.tests[0]);
		runSingleTest(context, suite.tests[0]);
	}
	// End warmup

	MonoTime start = currTime;
	foreach(ref test; suite.tests) {
		runSingleTest(context, test);
	}
	MonoTime end = currTime;
	writefln("Done %s tests in %s", suite.tests.length, end - start);

	return 0;
}

void runSingleTest(ref VmTestContext c, ref Test test) {
	c.prepareForTest(test);
	//writef("-- test");
	//foreach(ref param; test.parameters) {
	//	writef(" (%s %s)", param.id, param.value);
	//}
	//writeln;
	test.test_handler(c);

	static if (SLOW_CHECKS) {
		c.vm.reset;
	}
}
