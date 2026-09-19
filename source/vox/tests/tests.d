/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.tests.tests;

import vox.lib;
import vox.tests.infra;
import vox.tests.context;

@nogc nothrow:

@Test
@q{
--- test1.vx
	;
}
void test1(ref VoxTestContext c) {
	c.compileFail
		.expectDiagnostic("Expected declaration, got ;")
		.withAnnotation("here").pointingAt(";");
}

@Test
@q{
--- test2.vx
	i32 data;
}
void test2(ref VoxTestContext c) {
	c.compile();
}
