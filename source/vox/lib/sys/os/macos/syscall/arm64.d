/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.os.macos.syscall.arm64;

// https://github.com/opensource-apple/xnu/blob/master/bsd/kern/syscalls.master
enum sys_exit = 0x01;
enum sys_mmap = 0xc5;
enum sys_mprotect = 0x4a;
enum sys_munmap = 0x49;
enum sys_write = 0x04;
