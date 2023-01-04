/// Copyright: Copyright (c) 2023 Andrey Penechko.
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
/// Authors: Andrey Penechko.
module vox.lib.mem.os_allocator;

import vox.lib;

@nogc nothrow:

enum ALLOC_GRANULARITY = 65_536;

version(Posix) {
	ubyte[] os_allocate(size_t bytes) {
		if (!bytes) return null;
		import vox.lib.system.posix : mmap, MAP_ANON, PROT_READ, PROT_WRITE, MAP_PRIVATE, MAP_FAILED;
		enforce(bytes.paddingSize(ALLOC_GRANULARITY) == 0, "%s is not aligned to ALLOC_GRANULARITY (%s) ", bytes, ALLOC_GRANULARITY);
		void* p = mmap(null, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
		enforce(p != MAP_FAILED, "mmap failed: requested %s bytes", size);
		return cast(ubyte[])p[0 .. bytes];
	}

	void os_deallocate(ubyte[] b) {
		import vox.lib.system.posix : munmap;
		if (b.ptr is null) return;
		int res = munmap(b.ptr, b.length);
		enforce(res == 0, "munmap(%X, %s) failed, %s", b.ptr, b.length, res);
	}
} else version(Windows) {
	ubyte[] os_allocate(size_t bytes) {
		if (!bytes) return null;

		import vox.lib.system.windows : VirtualAlloc, GetLastError, PAGE_READWRITE, MEM_COMMIT, MEM_RESERVE;
		void* p = VirtualAlloc(null, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
		int errCode = GetLastError();
		enforce(p !is null, "VirtualAlloc failed: requested %s bytes, error %s", bytes, errCode);
		return cast(ubyte[])p[0 .. bytes];
	}

	void os_deallocate(ubyte[] b) {
		import vox.lib.system.windows : VirtualFree, MEM_RELEASE;
		if (b.ptr is null) return;
		VirtualFree(b.ptr, 0, MEM_RELEASE);
	}
} else version(WebAssembly) {
	ubyte[] os_allocate(size_t bytes) {
		if (!bytes) return null;
		import vox.lib.system.wasm_all : wasm_memory_grow;
		enforce(bytes.paddingSize(ALLOC_GRANULARITY) == 0, "%s is not aligned to ALLOC_GRANULARITY (%s) ", bytes, ALLOC_GRANULARITY);
		int res = wasm_memory_grow(0, bytes / ALLOC_GRANULARITY);
		enforce(res != -1, "wasm.memory.grow failed: requested %s bytes", bytes);
		return (cast(ubyte*)(res * ALLOC_GRANULARITY))[0 .. bytes];
	}

	void os_deallocate(ubyte[] b) {
	}
}
