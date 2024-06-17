/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.system.syscall.x64.linux;
version(linux):

import vox.lib.types;

enum READ = 0;
enum WRITE = 1;
enum MMAP = 9;
enum MPROTECT = 10;
enum MUNMAP = 11;
enum sys_exit = 60;
enum sys_exit_group = 231;
enum sys_futex = 202;
enum sys_clock_gettime = 228;
enum sys_clock_getres = 229;
enum sys_clone3 = 435;

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
