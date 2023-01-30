/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Test runner
module vox.vm.tests.infra.runner;

import vox.lib;
import vox.vm;
import vox.vm.tests.infra.test;
import vox.vm.tests.tests;

@nogc nothrow:

i32 runVmTests() {
	VoxAllocator allocator;

	enum static_bytes = 64*1024;
	enum heap_bytes = 64*1024;
	enum stack_bytes = 64*1024;

	VmState vm = {
		allocator : &allocator,
		readWriteMask : MemFlags.heap_RW | MemFlags.stack_RW | MemFlags.static_RW,
		ptrSize : 4,
	};

	vm.reserveMemory(static_bytes, heap_bytes, stack_bytes);

	auto ctx = VmTestContext(&vm, stdoutSink);

	Array!Test tests;
	vox.vm.tests.tests.vmTests(allocator, tests);

	writefln("Running %s tests", tests.length);

	// Warmup (first run does all the allocations and memory faults)
	vm.reset;
	tests[0].test_handler(ctx);
	vm.reset;
	tests[0].test_handler(ctx);
	// End warmup

	MonoTime start = currTime;

	foreach(ref test; tests) {
		vm.ptrSize = test.ptrSize;
		vm.reset;
		test.test_handler(ctx);
	}

	MonoTime end = currTime;

	writefln("Done %s tests in %s", tests.length, end - start);

	return 0;
}
