/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys.arch.arm64.chkstk;

import ldc.attributes;

version(NO_DEPS)
pragma(inline, false)
@naked
export
extern(C)
void __chkstk() {
	import ldc.llvmasm;
	// https://github.com/libsdl-org/SDL/blob/main/src/stdlib/SDL_mslibc_arm64.masm
	return __asm!void(`
		${:comment} x15 - Stack size divided by 16

		${:comment} x17 = stack low address
		ldr  x17, [x18, #16]
		${:comment} x16 = sp - (x15 << 4)
		subs x16, sp, x15, LSL #4
		${:comment} x16 = cc ? 0 : x16
		csel x16, xzr, x16, cc

		${:comment} Early exit when no probing needed
		cmp  x16, x17
		b.cc 1f
		ret
	1:
		and  x16, x16, #0xfffffffffffff000
	2:
		sub  x17, x17, #1, LSL #12
		ldr  xzr, [x17]
		cmp  x17, x16
		b.ne 2b
		ret
	`, "");
}
