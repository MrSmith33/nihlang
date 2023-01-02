/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.system.syscall.x64.macos;

version(OSX):

enum WRITE = 0x2000004;
enum EXIT = 0x2000001;
