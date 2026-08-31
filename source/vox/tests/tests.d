/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.tests.tests;

import vox.lib;
import vox.tests.infra;
import vox.tests.context;

@nogc nothrow:

@Test
//@TestOnly
@q{
--- test1.vx
	i32 data = 42;
--- test2.vx
	i32 data = 2;
}
void test_sandbox(ref VoxTestContext c) {
	c.driver.compile();

	//auto sym = c.getGlobalPtr!i32("test1.data");
	//assert(*sym == 42);
}
