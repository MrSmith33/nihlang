/// Copyright: Copyright (c) 2022-2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.os.linux.syscall.x64;

import vox.lib.types;

// https://github.com/torvalds/linux/blob/master/arch/x86/entry/syscalls/syscall_64.tbl
enum sys_clock_getres = 229;
enum sys_clock_gettime = 228;
enum sys_clone = 56;
enum sys_clone3 = 435;
enum sys_exit = 60;
enum sys_exit_group = 231;
enum sys_futex = 202;
enum sys_mmap = 9;
enum sys_mprotect = 10;
enum sys_munmap = 11;
enum sys_read = 0;
enum sys_write = 1;
