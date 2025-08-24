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

mixin template TestContextUtils() {
	@nogc nothrow:

	ITestContext toInterface() {
		ITestContext res = {
			instance : &this,
			runTestPtr : (&this.runTest).funcptr
		};
		return res;
	}
}
