/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.algo;

@nogc nothrow:


void swap(T)(ref T lhs, ref T rhs) pure {
	auto tmp = lhs;
	lhs = rhs;
	rhs = tmp;
}

version(VANILLA_D) {
	public import core.stdc.string : memmove;
}

version(NO_DEPS) version (LDC) {
	public import core.stdc.string : memmove;
}

version(NO_DEPS) version(DigitalMars)
extern(C) void memmove(void* dst, const(void)* src, size_t len)
{
	version (LDC) {
		import ldc.intrinsics : llvm_memmove;
		llvm_memmove!size_t(dst, src, len);
	} else {
		if (src < dst) {
			if (src + len <= dst) {
				dst[0..len] = src[0..len];
			} else {
				for (size_t size = len; size > 0; --size) {
					*cast(ubyte*)(dst+size-1) = *cast(ubyte*)(src+size-1);
				}
			}
		} else if (src > dst) {
			if (dst + len <= src) {
				dst[0..len] = src[0..len];
			} else {
				for (size_t size = len; size > 0; --size) {
					*cast(ubyte*)dst++ = *cast(ubyte*)src++;
				}
			}
		} else {
			// noop
		}
	}
}

/*void testMemmove() {
	ubyte[8] buf;

	buf = [1,2,3,4,5,6,7,8];
	memmove(&buf[4], &buf[0], 4);
	assert(buf == [1,2,3,4,1,2,3,4]);

	buf = [1,2,3,4,5,6,7,8];
	memmove(&buf[2], &buf[0], 6);
	assert(buf == [1,2,1,2,3,4,5,6]);

	buf = [1,2,3,4,5,6,7,8];
	memmove(&buf[0], &buf[0], 8);
	assert(buf == [1,2,3,4,5,6,7,8]);

	buf = [1,2,3,4,5,6,7,8];
	memmove(&buf[0], &buf[2], 6);
	assert(buf == [3,4,5,6,7,8,7,8]);

	buf = [1,2,3,4,5,6,7,8];
	memmove(&buf[0], &buf[4], 4);
	assert(buf == [5,6,7,8,5,6,7,8]);
}
*/
