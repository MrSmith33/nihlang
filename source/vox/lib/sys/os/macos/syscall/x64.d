/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.os.macos.syscall.x64;

// https://github.com/opensource-apple/xnu/blob/master/bsd/kern/syscalls.master
enum sys_exit = 0x2000001;
enum sys_mmap = 0x20000c5;
enum sys_mprotect = 0x200004a;
enum sys_munmap = 0x2000049;
enum sys_write = 0x2000004;
