/// Copyright: Copyright (c) 2017-2019,2026 Andrey Penechko.
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
/// Authors: Andrey Penechko.
module vox.lib.mem.arenapool;

// https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/mmap.2.html
// https://stackoverflow.com/questions/21809072/virtual-memory-on-osx-ios-versus-windows-commit-reserve-behaviour

///
struct ArenaPool
{
	import vox.lib;

	enum PAGE_SIZE = 65_536;
	ubyte[] buffer;
	size_t takenBytes;

	void reserve(size_t size) {
		size_t reservedBytes = alignValue(size, PAGE_SIZE); // round up to page size
		version(Windows) {
			import vox.lib.sys.os.windows : VirtualAlloc, MEM_RESERVE, PAGE_NOACCESS;
			ubyte* ptr = cast(ubyte*)VirtualAlloc(null, reservedBytes, MEM_RESERVE, PAGE_NOACCESS);
			enforce(ptr !is null, "VirtualAlloc failed: requested %s bytes", size);
		} else {
			ubyte* ptr = os_allocate(reservedBytes).ptr;
		}
		buffer = ptr[0..reservedBytes];
	}

	ubyte[] take(size_t numBytes) {
		if (numBytes == 0) return null;
		ubyte[] result = buffer[takenBytes..takenBytes+numBytes];
		takenBytes += numBytes;
		return result;
	}

	void decommitAll() {
		version(Posix) {
			import vox.lib.sys.os.posix : munmap;
			if (buffer.ptr is null) return;
			int res = munmap(buffer.ptr, buffer.length);
			enforce(res == 0, "munmap(%X, %s) failed, %s", buffer.ptr, buffer.length, res);
		} else version(Windows) {
			import vox.lib : VirtualFree, MEM_DECOMMIT;
			int res = VirtualFree(buffer.ptr, buffer.length, MEM_DECOMMIT);
			enforce(res != 0, "VirtualFree failed");
		}
	}
}
