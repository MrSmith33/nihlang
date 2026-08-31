/// Copyright: Copyright (c) 2017-2025 Andrey Penechko.
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
/// Authors: Andrey Penechko.
module vox.lib.mem.arena;

import vox.lib;

///
struct Arena(T)
{
	import vox.lib : alignValue, max, paddingSize;

	// Profiling stats:
	//    4k - 10.00% usage (12.9s)
	//   64k -  0.95% usage (11.6s)
	//  256k -  0.28% usage (11.5s)
	enum COMMIT_PAGE_SIZE = 65_536;

	T* bufPtr;
	/// How many items can be stored without commiting more memory (committed items)
	size_t capacity;
	/// Number of items in the buffer. length <= capacity
	size_t length;
	/// Total reserved bytes
	size_t reservedBytes;

	size_t committedBytes() { return alignValue(capacity * T.sizeof, COMMIT_PAGE_SIZE); }

	uint uintLength() { return cast(uint)length; }
	size_t byteLength() { return length * T.sizeof; }
	ref T opIndex(size_t at) { return bufPtr[at]; }
	ref T back() { return bufPtr[length-1]; }
	inout(T[]) data() inout { return bufPtr[0..length]; }
	size_t opDollar() const { return length; }
	bool empty() { return length == 0; }
	T* nextPtr() { return bufPtr + length; }
	bool contains(void* ptr) { return cast(void*)bufPtr <= ptr && cast(T*)ptr < cast(void*)(bufPtr + length); }

	void setBuffer(ubyte[] reservedBuffer) {
		setBuffer(reservedBuffer, reservedBuffer.length);
	}
	void setBuffer(ubyte[] reservedBuffer, size_t committedBytes) {
		bufPtr = cast(T*)reservedBuffer.ptr;
		assert(bufPtr, "reservedBuffer is null");
		reservedBytes = reservedBuffer.length;
		// we can lose [0; T.sizeof-1] bytes here, need to round up to multiple of allocation size when committing
		capacity = committedBytes / T.sizeof;
		length = 0;
	}
	void clear() { length = 0; }

	T[] put(const(T)[] items ...) {
		size_t initialLength = length;
		version(Windows) {
			if (capacity - length < items.length) makeSpace(items.length);
		}
		//writefln("assign %X.%s @ %s..%s+%s cap %s", bufPtr, T.sizeof, length, length, items.length, capacity);
		bufPtr[length..length+items.length] = items;
		length += items.length;
		return bufPtr[initialLength..length];
	}

	void stealthPut(T item) {
		version(Windows) {
			if (capacity == length) makeSpace(1);
		}
		bufPtr[length] = item;
	}

	/// Increases length and returns void-initialized slice to be filled by user
	T[] voidPut(size_t howMany) {
		version(Windows) {
			if (capacity - length < howMany) makeSpace(howMany);
		}
		length += howMany;
		return bufPtr[length-howMany..length];
	}

	void free(T[] array) {
		T* endPtr = bufPtr + length;
		T* arrayEndPtr = array.ptr + array.length;
		if (endPtr == arrayEndPtr) {
			length -= array.length;
		}
	}

	void unput(size_t numItems) {
		length -= numItems;
	}

	static if (is(T == ubyte))
	{
		void put(V)(auto ref V value)
			if (!is(immutable(V) == immutable(I)[], I))
		{
			ubyte[] ptr = voidPut(V.sizeof);
			ptr[] = *cast(ubyte[V.sizeof]*)&value;
		}

		void pad(size_t bytes) {
			voidPut(bytes)[] = 0;
		}

		void padUntilAligned(size_t alignment) {
			pad(paddingSize(length, alignment));
		}
	}

	inout(T)[] opSlice() inout {
		return bufPtr[0..length];
	}

	inout(T)[] opSlice(size_t from, size_t to) inout {
		assert(from < length);
		assert(to <= length);
		return bufPtr[from..to];
	}

	version(Windows)
	void makeSpace(size_t items) {
		assert(items > (capacity - length));
		size_t _committedBytes = committedBytes;
		size_t bytesToCommit = alignValue((items - (capacity - length)) * T.sizeof, COMMIT_PAGE_SIZE);
		bytesToCommit = max(bytesToCommit, COMMIT_PAGE_SIZE);

		if (_committedBytes + bytesToCommit > reservedBytes) {
			enforce(false, "Arena.makeSpace() out of memory: reserved %s, committed bytes %s, requested %s",
				reservedBytes, _committedBytes, bytesToCommit);
		}

		version(Windows) {
			import vox.lib.sys.os.windows.bind : VirtualAlloc, MEM_COMMIT, PAGE_READWRITE;
			void* result = VirtualAlloc(cast(ubyte*)bufPtr + _committedBytes, bytesToCommit, MEM_COMMIT, PAGE_READWRITE);
			if (result is null) assert(false, "Cannot commit more bytes");
		}

		capacity = (_committedBytes + bytesToCommit) / T.sizeof;
	}
}
