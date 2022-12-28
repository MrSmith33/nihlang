/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.utils.system.linux;

version(linux) version(X86_64) @nogc nothrow @system:

import vox.utils.types;

void writeString(const(char)[] str) {
	import vox.utils.system.syscall : syscall, WRITE;
	syscall(WRITE, 1, cast(usize)str.ptr, str.length);
}

noreturn vox_exit_process(u32 exitCode) {
	import vox.utils.system.syscall : syscall, EXIT;
	syscall(EXIT, exitCode);
	assert(0);
}
