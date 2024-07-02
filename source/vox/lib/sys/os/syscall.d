/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.os.syscall;

version(linux) public import vox.lib.sys.os.linux.syscall;
version(OSX)   public import vox.lib.sys.os.macos.syscall;
