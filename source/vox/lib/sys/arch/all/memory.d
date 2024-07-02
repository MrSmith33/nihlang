/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

// Arch-independent implementation of memset, memcpy, memmove, and memcmp
// Don't use llvm intrinsic, as it simply calls libc function, causing infinite recursion
module vox.lib.sys.arch.all.memory;

extern(C) @nogc nothrow @system:

void memmove(void* dst, const(void)* src, size_t len)
{
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

int memcmp(const(void)* buf1, const(void)* buf2, size_t len) {
	if(!len) return 0;
	while(--len && *cast(ubyte*)buf1 == *cast(ubyte*)buf2) {
		++buf1;
		++buf2;
	}
	return *cast(ubyte*)buf1 - *cast(ubyte*)buf2;
}

void* memset(void* dest, ubyte val, size_t len) {
	for(size_t i = 0; i < len; ++i) (cast(ubyte*)dest)[i] = val;
	return dest;
}

void* memcpy(void* dest, const void* src, size_t len) {
	for(size_t i = 0; i < len; ++i) (cast(ubyte*)dest)[i] = (cast(ubyte*)src)[i];
	return dest;
}
