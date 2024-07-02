/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.arch.arm64.syscall;

@nogc nothrow @system:

import ldc.attributes;
import ldc.llvmasm;

ulong syscall(ulong id) {
	return __asm!ulong("svc #0", "={x0}, {x8}", id);
}

ulong syscall(ulong id, ulong arg0) {
	return __asm!ulong("svc #0", "={x0}, {x8}, {x0}", id, arg0);
}

ulong syscall(ulong id, ulong arg0, ulong arg1) {
	return __asm!ulong("svc #0", "={x0}, {x8}, {x0}, {x1}", id, arg0, arg1);
}

ulong syscall(ulong id, ulong arg0, ulong arg1, ulong arg2) {
	return __asm!ulong("svc #0", "={x0}, {x8}, {x0}, {x1}, {x2}", id, arg0, arg1, arg2);
}

ulong syscall(ulong id, ulong arg0, ulong arg1, ulong arg2, ulong arg3) {
	return __asm!ulong("svc #0", "={x0}, {x8}, {x0}, {x1}, {x2}, {x3}", id, arg0, arg1, arg2, arg3);
}

ulong syscall(ulong id, ulong arg0, ulong arg1, ulong arg2, ulong arg3, ulong arg4) {
	return __asm!ulong("svc #0", "={x0}, {x8}, {x0}, {x1}, {x2}, {x3}, {x4}", id, arg0, arg1, arg2, arg3, arg4);
}

ulong syscall(ulong id, ulong arg0, ulong arg1, ulong arg2, ulong arg3, ulong arg4, ulong arg5) {
	return __asm!ulong("svc #0", "={x0}, {x8}, {x0}, {x1}, {x2}, {x3}, {x4}, {x5}", id, arg0, arg1, arg2, arg3, arg4, arg5);
}
