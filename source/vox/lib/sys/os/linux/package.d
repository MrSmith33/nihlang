/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

// Code common for all linux platforms (arch-independent)
module vox.lib.sys.os.linux;

@nogc nothrow @system:
import vox.lib.types;
import vox.lib.sys.arch.syscall : syscall;

struct timespec {
	i64 tv_sec;
	i64 tv_nsec;
}

struct clone_args {
	u64 flags;        // Flags bit mask
	u64 pidfd;        // Where to store PID file descriptor (i32*)
	u64 child_tid;    // Where to store child TID, in child's memory (pid_t*)
	u64 parent_tid;   // Where to store child TID, in parent's memory (pid_t*)
	u64 exit_signal;  // Signal to deliver to parent on child termination
	u64 stack;        // Pointer to lowest byte of stack
	u64 stack_size;   // Size of stack
	u64 tls;          // Location of new TLS
	u64 set_tid;      // Pointer to a pid_t array (since Linux 5.5)
	u64 set_tid_size; // Number of elements in set_tid (since Linux 5.5)
	u64 cgroup;       // File descriptor for target cgroup of child (since Linux 5.7)
}


i32 clock_gettime(i32 clockid, timespec* tp) {
	import vox.lib.sys.os.linux.syscall : sys_clock_gettime;
	return cast(i32)syscall(sys_clock_gettime, cast(u64)clockid, cast(u64)tp);
}

// timeout - null means infinite
i32 futex_wait(u32* address, u32 expected, timespec* timeout = null) {
	import vox.lib.sys.os.linux.syscall : sys_futex;
	enum FUTEX_WAIT_PRIVATE = 128;
	return cast(i32)syscall(sys_futex, cast(u64)address,
		FUTEX_WAIT_PRIVATE, expected, cast(u64)timeout);
}

i32 futex_wake(u32* address, u32 count) {
	import vox.lib.sys.os.linux.syscall : sys_futex;
	enum FUTEX_WAKE_PRIVATE = 1 | 128;
	return cast(i32)syscall(sys_futex, cast(u64)address,
		FUTEX_WAKE_PRIVATE, count);
}

i32 clone3(clone_args* uargs, usz size) {
	import vox.lib.sys.os.linux.syscall : sys_clone3;
	return cast(i32)syscall(sys_clone3, cast(ulong)uargs, size);
}

enum CLOCK_MONOTONIC = 1;

enum MAP_ANON  = 0x0020;
enum MS_SYNC   = 0x0004;
