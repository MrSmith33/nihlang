/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.system.posix;

import vox.lib.types;

version(Posix) version(X86_64) @nogc nothrow @system:

void writeString(const(char)[] str) {
	import vox.lib.system.syscall : syscall, WRITE;
	syscall(WRITE, 1, cast(usize)str.ptr, str.length);
}

void* mmap(void* addr, size_t len, int prot, int flags, int fd, long off) {
	import vox.lib.system.syscall : syscall, MMAP;
	return cast(void*)syscall(MMAP, cast(ulong)addr, len, prot, flags, fd, off);
}

int mprotect(void* addr, size_t len, int prot) {
	import vox.lib.system.syscall : syscall, MPROTECT;
	return cast(int)syscall(MPROTECT, cast(ulong)addr, len, prot);
}

int munmap(void* addr, size_t len) {
	import vox.lib.system.syscall : syscall, MUNMAP;
	return cast(int)syscall(MUNMAP, cast(ulong)addr, len);
}

enum PROT_NONE     = 0x0000;
enum PROT_READ     = 0x0001;
enum PROT_WRITE    = 0x0002;
enum PROT_EXEC     = 0x0004;

enum MAP_FAILED    = cast(void*)-1;
enum MAP_SHARED    = 0x0001;
enum MAP_PRIVATE   = 0x0002;
enum MAP_FIXED     = 0x0010;
enum MAP_GROWSDOWN = 0x00100;
enum MAP_STACK     = 0x20000;

enum MS_ASYNC      = 0x0001;
enum MS_INVALIDATE = 0x0002;


version (all) {
version (linux) {
	enum MAP_ANON  = 0x0020;
	enum MS_SYNC   = 0x0004;
} else version (OSX) {
	enum MAP_ANON  = 0x1000;
	enum MS_SYNC   = 0x0010;
} else { static assert(false, "Platform not implemented"); }
}
