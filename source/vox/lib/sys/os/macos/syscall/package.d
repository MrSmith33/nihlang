/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.os.macos.syscall;

version(X86_64)  public import vox.lib.sys.os.macos.syscall.x64;
version(AArch64) public import vox.lib.sys.os.macos.syscall.arm64;
