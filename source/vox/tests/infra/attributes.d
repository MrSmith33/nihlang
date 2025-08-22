/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Test attributes
module vox.tests.infra.attributes;

import vox.lib;
import vox.tests.infra;

@nogc nothrow:

enum Test;
enum TestIgnore;
enum TestOnly;
enum TestPtrSize32;
enum TestPtrSize64;
struct TestParam {
	u8 id;
	u32[] values;
}
