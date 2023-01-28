/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.system.linux;

version(linux) version(X86_64) @nogc nothrow @system:

import vox.lib.types;

enum CLOCK_MONOTONIC = 1;

struct timespec {
	long  tv_sec;
	int   tv_nsec;
}

int clock_gettime(int clockid, timespec* tp) {
	import vox.lib.system.syscall : syscall, sys_clock_gettime;
	return cast(int)syscall(sys_clock_gettime, cast(ulong)clockid, cast(ulong)tp);
}
