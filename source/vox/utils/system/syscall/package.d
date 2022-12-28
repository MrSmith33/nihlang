/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.utils.system.syscall;

version(X86_64) {
	public import vox.utils.system.syscall.x64;
}
