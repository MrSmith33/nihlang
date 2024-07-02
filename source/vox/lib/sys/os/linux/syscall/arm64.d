/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.os.linux.syscall.arm64;

import vox.lib.types;

// https://github.com/torvalds/linux/blob/v6.7/include/uapi/asm-generic/unistd.h
// https://arm64.syscall.sh/
enum sys_clock_getres = 114;
enum sys_clock_gettime = 113;
enum sys_clone = 220;
enum sys_clone3 = 435;
enum sys_exit = 93;
enum sys_exit_group = 94;
enum sys_futex = 98;
enum sys_mmap = 222;
enum sys_mprotect = 226;
enum sys_munmap = 215;
enum sys_read = 63;
enum sys_write = 64;
