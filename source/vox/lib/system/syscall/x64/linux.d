/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.system.syscall.x64.linux;
version(linux):

enum READ = 0;
enum WRITE = 1;
enum MMAP = 9;
enum MPROTECT = 10;
enum MUNMAP = 11;
enum EXIT = 60;
enum sys_futex = 202;
enum sys_clock_gettime = 228;
enum sys_clock_getres = 229;
