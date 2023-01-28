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
	enum PTR_SIZE = 4;

	VmState vm = {
		allocator : &allocator,
		readWriteMask : MemFlags.heap_RW | MemFlags.stack_RW | MemFlags.static_RW,
		ptrSize : PTR_SIZE,
	};

	vm.reserveMemory(static_bytes, heap_bytes, stack_bytes);

	auto ctx = VmTestContext(&vm);

	Array!Test tests;
	vox.vm.tests.tests.vmTests(allocator, tests);

	writefln("Running %s tests", tests.length);

	MonoTime start = currTime;

	foreach(ref test; tests) {
		test.tester(ctx);
	}

	MonoTime end = currTime;

	writefln("Done %s tests in %s", tests.length, end - start);

	return 0;
}