/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

// Auto-import target arch-os syscalls
module vox.lib.sys.syscall;

// arch-specific code
public import vox.lib.sys.arch.syscall;
// os-specific code
public import vox.lib.sys.os.syscall;
