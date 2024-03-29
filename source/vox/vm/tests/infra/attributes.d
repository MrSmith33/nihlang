/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Test attributes
module vox.vm.tests.infra.attributes;

import vox.lib;
import vox.vm.tests.infra;

@nogc nothrow:

enum VmTest;
enum VmTestIgnore;
enum VmTestOnly;
enum TestPtrSize32;
enum TestPtrSize64;
struct VmTestParam {
	TestParamId id;
	u32[] values;
}

enum TestParamId : u8 {
	ptr_size,
	instr,
	memory,
	user,
}
