/// Copyright: Copyright (c) 2023 Andrey Penechko.
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
/// Authors: Andrey Penechko.
module vox.lib.mem.allocator;

import vox.lib;

@nogc nothrow:

enum ALLOC_GRANULARITY = 65_536;

version(Posix) {
	ubyte[] os_allocate(size_t bytes) {
		if (!bytes) return null;
		import vox.lib.sys.os.posix : mmap, MAP_ANON, PROT_READ, PROT_WRITE, MAP_PRIVATE, MAP_FAILED;
		enforce(bytes.paddingSize(ALLOC_GRANULARITY) == 0, "%s is not aligned to ALLOC_GRANULARITY (%s) ", bytes, ALLOC_GRANULARITY);
		void* p = mmap(null, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
		enforce(p != MAP_FAILED, "mmap failed: requested %s bytes", bytes);
		return cast(ubyte[])p[0 .. bytes];
	}
	void os_deallocate(ubyte[] b) {
		import vox.lib.sys.os.posix : munmap;
		if (b.ptr is null) return;
		int res = munmap(b.ptr, b.length);
		enforce(res == 0, "munmap(%X, %s) failed, %s", b.ptr, b.length, res);
	}
} else version(Windows) {
	ubyte[] os_allocate(size_t bytes) {
		if (!bytes) return null;
		import vox.lib.sys.os.windows : VirtualAlloc, GetLastError, PAGE_READWRITE, MEM_COMMIT, MEM_RESERVE;
		enforce(bytes.paddingSize(ALLOC_GRANULARITY) == 0, "%s is not aligned to ALLOC_GRANULARITY (%s) ", bytes, ALLOC_GRANULARITY);
		void* p = VirtualAlloc(null, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
		int errCode = GetLastError();
		enforce(p !is null, "VirtualAlloc failed: requested %s bytes, error %s", bytes, errCode);
		return cast(ubyte[])p[0 .. bytes];
	}
	void os_deallocate(ubyte[] b) {
		import vox.lib.sys.os.windows : VirtualFree, MEM_RELEASE;
		if (b.ptr is null) return;
		VirtualFree(b.ptr, 0, MEM_RELEASE);
	}
} else version(WebAssembly) {
	ubyte[] os_allocate(size_t bytes) {
		if (!bytes) return null;
		import vox.lib.sys.arch.wasm : wasm_memory_grow;
		enforce(bytes.paddingSize(ALLOC_GRANULARITY) == 0, "%s is not aligned to ALLOC_GRANULARITY (%s) ", bytes, ALLOC_GRANULARITY);
		int res = wasm_memory_grow(0, bytes / ALLOC_GRANULARITY);
		enforce(res != -1, "wasm.memory.grow failed: requested %s bytes", bytes);
		return (cast(ubyte*)(res * ALLOC_GRANULARITY))[0 .. bytes];
	}
	void os_deallocate(ubyte[] b) {
	}
}

struct FreeList {
	@nogc nothrow:

	void* head;
	ubyte[] get(size_t size) {
		if (head) {
			void** linkPtr = cast(void**)head;
			head = linkPtr[0];
			return (cast(ubyte*)linkPtr)[0..size];
		}
		return null;
	}
	void put(ubyte[] block) {
		void** linkPtr = cast(void**)block.ptr;
		linkPtr[0] = head;
		head = cast(void*)block.ptr;
	}
}

struct BlockAllocator {
	@nogc nothrow:

	FreeList freeList;
	ubyte* nextItemPtr;
	u32 blockItemsLeft;
	u32 allocatedItems;

	enum BLOCK_SIZE = ALLOC_GRANULARITY;

	ubyte[] alloc(size_t size) {
		ubyte[] block = freeList.get(size);
		if (block) {
			++allocatedItems;
			return block;
		}

		if (blockItemsLeft == 0) {
			nextItemPtr = os_allocate(BLOCK_SIZE).ptr;
			blockItemsLeft = BLOCK_SIZE / size;
		}

		auto ptr = nextItemPtr;
		nextItemPtr += size;
		--blockItemsLeft;
		++allocatedItems;
		return ptr[0..size];
	}

	void free(ubyte[] block) {
		freeList.put(block);
	}
}

struct VoxAllocator
{
	@nogc nothrow:
	import vox.lib : isPowerOfTwo, bsr;

	// arenas for buffers from 16 to 65536 bytes
	enum NUM_ARENAS = 13;
	enum MIN_BLOCK_BYTES = 16;
	enum MAX_BLOCK_BYTES = 65_536;

	private BlockAllocator[NUM_ARENAS] sizeAllocators;

	ubyte[] allocBlock(size_t size) {
		assert(isPowerOfTwo(size));
		assert(size >= MIN_BLOCK_BYTES);
		if (size > MAX_BLOCK_BYTES) {
			return os_allocate(alignValue(size, ALLOC_GRANULARITY));
		}
		uint index = sizeToIndex(size);
		return sizeAllocators[index].alloc(size);
	}

	void freeBlock(ubyte[] block) {
		if (block.ptr is null) return;
		assert(isPowerOfTwo(block.length));
		assert(block.length >= MIN_BLOCK_BYTES);
		if (block.length > MAX_BLOCK_BYTES) {
			return os_deallocate(block);
		}
		uint index = sizeToIndex(block.length);
		sizeAllocators[index].free(block);
	}

	private uint sizeToIndex(size_t size) {
		// from 16 32 64 128 256 512 1024 2048 4096 8192 16384 32768 65536
		//   to  0  1  2   3   4   5    6    7    8    9    10    11    12
		uint index = bsr(size) - 4;
		return index;
	}
}
