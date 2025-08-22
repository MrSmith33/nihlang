/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Data structures
module vox.tests.infra.context;

import vox.lib;
import vox.tests.infra;

@nogc nothrow:

struct ITestContext {
	@nogc nothrow:

	void* instance;
	@nogc nothrow void function(ref TestInstance) runTestPtr;

	void runTest(ref TestInstance test) {
		@nogc nothrow void delegate(ref TestInstance) fun;
		fun.ptr = instance;
		fun.funcptr = runTestPtr;
		fun(test);
	}
}

struct BaseTestContext(T) {
	@nogc nothrow:
	SinkDelegate sink;
	TestInstance test;

	ITestContext toInterface() {
		auto realThis = cast(T*)&this;
		ITestContext res = {
			instance : realThis,
			runTestPtr : (&realThis.runTest).funcptr
		};
		return res;
	}
}
