/// Copyright: Copyright (c) 2017-2019 Andrey Penechko.
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
/// Authors: Andrey Penechko.
module vox.lib.mem.array;

// Optimal for 1, 2, 4 byte items.
// Best with POT sized items
// Can store inline up to 8 bytes
struct Array(T)
{
	@nogc nothrow:
	import vox.lib.math : isPowerOfTwo, nextPOT, max;
	import vox.lib.format : SinkDelegate, FormatSpec, formattedWrite;
	import vox.lib.error : enforce;
	import vox.lib.algo : memmove;
	import vox.lib.mem.allocator : VoxAllocator;

	// Can be 0
	enum uint NUM_INLINE_BYTES = size_t.sizeof;
	enum uint NUM_INLINE_ITEMS = NUM_INLINE_BYTES / T.sizeof;
	enum uint MIN_EXTERNAL_BYTES = max(VoxAllocator.MIN_BLOCK_BYTES, nextPOT((size_t.sizeof / T.sizeof + 1) * T.sizeof));

	private uint _length;
	private uint _capacity = NUM_INLINE_ITEMS;

	union
	{
		// Used when length <= NUM_INLINE_ITEMS
		private T[NUM_INLINE_ITEMS] inlineItems;

		// Used when length > NUM_INLINE_ITEMS
		private T* externalArray;
	}

	bool empty() const { return _length == 0; }
	uint length() const { return _length; }
	uint opDollar() const { return _length; }
	uint capacity() const { return _capacity; }
	ref T front() { return this[0]; }
	ref T back() { return this[$-1]; }
	void clear() { _length = 0; }

	ref inout(T) opIndex(size_t index) inout
	{
		enforce(index < _capacity, "opIndex(%s), capacity %s", index, _capacity);
		static if (NUM_INLINE_ITEMS > 0) {
			if (_capacity == NUM_INLINE_ITEMS) return inlineItems[index];
		}

		return externalArray[index];
	}

	Array!T dup(ref VoxAllocator allocator)
	{
		Array!T copy = this;

		static if (NUM_INLINE_ITEMS > 0) {
			if (_capacity == NUM_INLINE_ITEMS) return copy;
		}

		size_t byteCapacity = nextPOT(_capacity * T.sizeof);

		// When we have empty array with NUM_INLINE_ITEMS == 0 and no allocated external array
		if (byteCapacity == 0) return copy;

		ubyte[] block = (cast(ubyte*)externalArray)[0..byteCapacity];

		ubyte[] newBlock = allocator.allocBlock(block.length);
		newBlock[] = block;
		copy.externalArray = cast(T*)newBlock.ptr;
		return copy;
	}

	T[] voidPut(ref VoxAllocator allocator, uint howMany)
	{
		if (_length + howMany > _capacity) extend(allocator, howMany);
		_length += howMany;
		return this[_length-howMany.._length];
	}

	void put(ref VoxAllocator allocator, T[] items...)
	{
		if (_length + items.length > _capacity) extend(allocator, cast(uint)items.length);

		_length += items.length;
		this[_length-items.length..$][] = items;
	}

	void putFront(ref VoxAllocator allocator, T item)
	{
		putAt(allocator, 0, item);
	}

	// shifts items to the right
	void putAt(ref VoxAllocator allocator, size_t at, T[] items...)
	{
		replaceAt(allocator, at, 0, items);
	}

	void replaceAt(ref VoxAllocator allocator, size_t at, size_t numItemsToRemove, T[] itemsToInsert)
	{
		assert(at + numItemsToRemove <= _length);

		size_t numItemsToInsert = itemsToInsert.length;

		replaceAtVoid(allocator, at, numItemsToRemove, numItemsToInsert);
		this[at..at+numItemsToInsert][] = itemsToInsert;
	}

	void replaceAtVoid(ref VoxAllocator allocator, size_t at, size_t numItemsToRemove, size_t numItemsToInsert)
	{
		assert(at + numItemsToRemove <= _length);

		if (numItemsToInsert == numItemsToRemove)
		{
			// no resize or moves needed
		}
		else
		{
			ptrdiff_t delta = numItemsToInsert - numItemsToRemove;

			if (_length + delta > _capacity) extend(allocator, cast(uint)delta);

			scope(exit) _length += delta;

			size_t start = at + numItemsToRemove;
			size_t numItemsToMove = _length - start;
			T* ptr = externalArray + start;

			static if (NUM_INLINE_ITEMS > 0) {
				if (_capacity == NUM_INLINE_ITEMS) ptr = inlineItems.ptr + start;
			}

			memmove(ptr + delta, ptr, numItemsToMove * T.sizeof);
		}
	}

	void unput(size_t numItems)
	{
		_length = cast(uint)(_length - numItems);
	}

	void reserve(ref VoxAllocator allocator, uint howMany)
	{
		if (_length + howMany > _capacity) extend(allocator, howMany);
	}

	// returns memory to allocator and zeroes the length
	void free(ref VoxAllocator allocator) {
		scope(exit) {
			externalArray = null;
			_length = 0;
			_capacity = NUM_INLINE_ITEMS;
		}
		static if (NUM_INLINE_ITEMS > 0) {
			if (_capacity == NUM_INLINE_ITEMS) return; // no-op
		}

		size_t byteCapacity = nextPOT(_capacity * T.sizeof);
		ubyte[] oldBlock = (cast(ubyte*)externalArray)[0..byteCapacity];
		allocator.freeBlock(oldBlock);
	}

	// extend the storage
	private void extend(ref VoxAllocator allocator, uint items)
	{
		uint byteCapacityNeeded = cast(uint)nextPOT((_length + items) * T.sizeof);
		if (_capacity == NUM_INLINE_ITEMS) {
			ubyte[] newBlock = allocator.allocBlock(max(byteCapacityNeeded, MIN_EXTERNAL_BYTES));
			static if (NUM_INLINE_ITEMS > 0) {
				ubyte[] oldBlock = (cast(ubyte*)inlineItems.ptr)[0..NUM_INLINE_BYTES];
				newBlock[0..oldBlock.length] = oldBlock;
			}
			externalArray = cast(T*)newBlock.ptr;
			_capacity = cast(uint)(newBlock.length / T.sizeof);
			return;
		}

		size_t byteCapacity = nextPOT(_capacity * T.sizeof);
		ubyte[] block = (cast(ubyte*)externalArray)[0..byteCapacity];
		resizeSmallArray(allocator, block, byteCapacityNeeded);
		externalArray = cast(T*)block.ptr;
		_capacity = cast(uint)(block.length / T.sizeof);
	}

	// Doubles the size of block
	private void resizeSmallArray(ref VoxAllocator allocator, ref ubyte[] oldBlock, size_t newLength) {
		assert(isPowerOfTwo(oldBlock.length));
		assert(oldBlock.length >= VoxAllocator.MIN_BLOCK_BYTES);
		assert(newLength >= VoxAllocator.MIN_BLOCK_BYTES, "too small");

		ubyte[] newBlock = allocator.allocBlock(newLength);
		newBlock[0..oldBlock.length] = oldBlock;
		allocator.freeBlock(oldBlock);
		oldBlock = newBlock;
	}

	inout(T)[] opSlice() inout
	{
		static if (NUM_INLINE_ITEMS > 0) {
			if (_capacity == NUM_INLINE_ITEMS) return inlineItems.ptr[0.._length];
		}
		return externalArray[0.._length];
	}

	inout(T)[] opSlice(size_t from, size_t to) inout
	{
		return this[][from..to];
	}

	void removeInPlace(size_t at)
	{
		if (at+1 != _length)
		{
			this[at] = this[_length-1];
		}
		--_length;
	}

	void removeByShift(size_t at, size_t numToRemove = 1)
	{
		size_t to = at;
		size_t from = at + numToRemove;
		while(from < _length)
		{
			this[to] = this[from];
			++to;
			++from;
		}
		_length -= numToRemove;
	}

	void toString(scope SinkDelegate sink, FormatSpec spec) const {
		sink("[");
		size_t i;
		foreach(const ref T item; opSlice()) {
			if (i > 0) sink(", ");
			sink.formattedWrite("%s", item);
			++i;
		}
		sink("]");
	}
}
