/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module utils.windows.linux;

version(linux) @nogc nothrow @system:

import vox.utils.posix;
import vox.utils.types;

void writeString(const(char)[] str) @nogc nothrow {
	syscall(1, 1, cast(usize)str.ptr, str.length);
}

noreturn vox_exit_process(u32 exitCode) @nogc nothrow {
	syscall(60, exitCode);
	assert(0);
}
