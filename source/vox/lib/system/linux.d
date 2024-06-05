/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.system.linux;

version(linux) version(X86_64) @nogc nothrow @system:

import vox.lib.types;

enum CLOCK_MONOTONIC = 1;

struct timespec {
	i64 tv_sec;
	i64 tv_nsec;
}

i32 clock_gettime(i32 clockid, timespec* tp) {
	import vox.lib.system.syscall : syscall, sys_clock_gettime;
	return cast(i32)syscall(sys_clock_gettime, cast(u64)clockid, cast(u64)tp);
}

// timeout - null means infinite
i32 futex_wait(u32* address, u32 expected, timespec* timeout = null) {
	import vox.lib.system.syscall : syscall, sys_futex;
	enum FUTEX_WAIT_PRIVATE = 128;
	return cast(i32)syscall(sys_futex, cast(u64)address,
		FUTEX_WAIT_PRIVATE, expected, cast(u64)timeout);
}

i32 futex_wake(u32* address, u32 count) {
	import vox.lib.system.syscall : syscall, sys_futex;
	enum FUTEX_WAKE_PRIVATE = 1 | 128;
	return cast(i32)syscall(sys_futex, cast(u64)address,
		FUTEX_WAKE_PRIVATE, count);
}
