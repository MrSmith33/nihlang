/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.types;

import vox.lib;

enum PtrSize : u8 {
	_32 = 0,
	_64 = 1,
}

enum TestParamId : u8 {
	ptr_size,
	instr,
	memory,
	user,
}
