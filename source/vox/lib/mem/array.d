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
	import vox.lib.error : Result, enforce;
	import vox.lib.memory : memmove;
	import vox.lib.mem.allocator : Allocator;

	// Can be 0
	enum uint NUM_INLINE_BYTES = size_t.sizeof;
	enum uint NUM_INLINE_ITEMS = NUM_INLINE_BYTES / T.sizeof;
	enum uint MIN_EXTERNAL_BYTES = max(Allocator.MIN_BLOCK_BYTES, nextPOT((size_t.sizeof / T.sizeof + 1) * T.sizeof));

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

	ref inout(T) opIndex(size_t index) inout {
		enforce(index < _capacity, "opIndex(%s), capacity %s", index, _capacity);
		static if (NUM_INLINE_ITEMS > 0) {
			if (_capacity == NUM_INLINE_ITEMS) return inlineItems[index];
		}

		return externalArray[index];
	}

	Result!(Array!T) dup(ref Allocator allocator) {
		Array!T copy = this;

		static if (NUM_INLINE_ITEMS > 0) {
			if (_capacity == NUM_INLINE_ITEMS) return typeof(return)(copy);
		}

		size_t byteCapacity = nextPOT(_capacity * T.sizeof);

		// When we have empty array with NUM_INLINE_ITEMS == 0 and no allocated external array
		if (byteCapacity == 0) return typeof(return)(copy);

		ubyte[] block = (cast(ubyte*)externalArray)[0..byteCapacity];

		auto newBlock = allocator.allocBlock(block.length);
		if (newBlock.isError) return typeof(return).makeError(1);
		newBlock.data[] = block;
		copy.externalArray = cast(T*)newBlock.data.ptr;
		return typeof(return)(copy);
	}

	Result!(T[]) voidPut(ref Allocator allocator, uint howMany) {
		if (_length + howMany > _capacity) {
			if (extend(allocator, howMany).isError)
				return Result!(T[]).makeError(1);
		}
		_length += howMany;
		return this[_length-howMany.._length].Result!(T[]);
	}

	Result!void put(ref Allocator allocator, const(T)[] items...) {
		if (_length + items.length > _capacity) {
			if (extend(allocator, cast(uint)items.length).isError)
				return Result!void.makeError(1);
		}

		_length += items.length;
		this[_length-items.length..$][] = cast(T[])items;
		return Result!void();
	}

	static if (is(T == ubyte))
	{
		Result!void putAsBytes(V)(ref Allocator allocator, auto ref V value)
			if (!is(immutable(V) == immutable(I)[], I))
		{
			auto ptr = voidPut(allocator, V.sizeof);
			if (ptr.isError) return typeof(return).makeError(1);
			ptr.data[] = *cast(ubyte[V.sizeof]*)&value;
			return typeof(return)();
		}
	}

	Result!void putFront(ref Allocator allocator, T item) {
		return putAt(allocator, 0, item);
	}

	// shifts items to the right
	Result!void putAt(ref Allocator allocator, size_t at, T[] items...) {
		return replaceAt(allocator, at, 0, items);
	}

	Result!void replaceAt(ref Allocator allocator, size_t at, size_t numItemsToRemove, T[] itemsToInsert) {
		assert(at + numItemsToRemove <= _length);

		size_t numItemsToInsert = itemsToInsert.length;

		if (replaceAtVoid(allocator, at, numItemsToRemove, numItemsToInsert).isError) {
			return Result!void.makeError(1);
		}
		this[at..at+numItemsToInsert][] = itemsToInsert;
		return Result!void();
	}

	Result!void replaceAtVoid(ref Allocator allocator, size_t at, size_t numItemsToRemove, size_t numItemsToInsert) {
		assert(at + numItemsToRemove <= _length);

		if (numItemsToInsert == numItemsToRemove) {
			// no resize or moves needed
		} else {
			ptrdiff_t delta = numItemsToInsert - numItemsToRemove;

			if (_length + delta > _capacity) {
				if (extend(allocator, cast(uint)delta).isError) {
					return Result!void.makeError(1);
				}
			}

			scope(exit) _length += delta;

			size_t start = at + numItemsToRemove;
			size_t numItemsToMove = _length - start;
			T* ptr = externalArray + start;

			static if (NUM_INLINE_ITEMS > 0) {
				if (_capacity == NUM_INLINE_ITEMS) ptr = inlineItems.ptr + start;
			}

			memmove(ptr + delta, ptr, numItemsToMove * T.sizeof);
		}
		return Result!void();
	}

	void unput(size_t numItems) {
		_length = cast(uint)(_length - numItems);
	}

	Result!void reserve(ref Allocator allocator, uint howMany) {
		if (_length + howMany > _capacity) {
			return extend(allocator, howMany);
		}
		return Result!void();
	}

	// returns memory to allocator and zeroes the length
	Result!void free(ref Allocator allocator) {
		scope(exit) {
			externalArray = null;
			_length = 0;
			_capacity = NUM_INLINE_ITEMS;
		}
		static if (NUM_INLINE_ITEMS > 0) {
			if (_capacity == NUM_INLINE_ITEMS) return Result!void(); // no-op
		}

		size_t byteCapacity = nextPOT(_capacity * T.sizeof);
		ubyte[] oldBlock = (cast(ubyte*)externalArray)[0..byteCapacity];
		return allocator.freeBlock(oldBlock);
	}

	// extend the storage
	private Result!void extend(ref Allocator allocator, uint items)
	{
		uint byteCapacityNeeded = cast(uint)nextPOT((_length + items) * T.sizeof);
		if (_capacity == NUM_INLINE_ITEMS) {
			auto newBlock = allocator.allocBlock(max(byteCapacityNeeded, MIN_EXTERNAL_BYTES));
			if (newBlock.isError) {
				return Result!void.makeError(1);
			}
			static if (NUM_INLINE_ITEMS > 0) {
				ubyte[] oldBlock = (cast(ubyte*)inlineItems.ptr)[0..NUM_INLINE_BYTES];
				newBlock.data[0..oldBlock.length] = oldBlock;
			}
			externalArray = cast(T*)newBlock.data.ptr;
			_capacity = cast(uint)(newBlock.data.length / T.sizeof);
			return Result!void();
		}

		size_t byteCapacity = nextPOT(_capacity * T.sizeof);
		ubyte[] block = (cast(ubyte*)externalArray)[0..byteCapacity];
		if (resizeSmallArray(allocator, block, byteCapacityNeeded).isError)
			return Result!void.makeError(1);
		externalArray = cast(T*)block.ptr;
		_capacity = cast(uint)(block.length / T.sizeof);
		return Result!void();
	}

	// Doubles the size of block
	private Result!void resizeSmallArray(ref Allocator allocator, ref ubyte[] oldBlock, size_t newLength) {
		assert(isPowerOfTwo(oldBlock.length));
		assert(oldBlock.length >= Allocator.MIN_BLOCK_BYTES);
		assert(newLength >= Allocator.MIN_BLOCK_BYTES, "too small");

		auto newBlock = allocator.allocBlock(newLength);
		if (newBlock.isError) {
			return Result!void.makeError(1);
		}
		newBlock.data[0..oldBlock.length] = oldBlock;
		allocator.freeBlock(oldBlock);
		oldBlock = newBlock.data;
		return Result!void();
	}

	inout(T)[] opSlice() inout {
		static if (NUM_INLINE_ITEMS > 0) {
			if (_capacity == NUM_INLINE_ITEMS) return inlineItems.ptr[0.._length];
		}
		return externalArray[0.._length];
	}

	inout(T)[] opSlice(size_t from, size_t to) inout {
		return this[][from..to];
	}

	void removeInPlace(size_t at) {
		if (at+1 != _length) {
			this[at] = this[_length-1];
		}
		--_length;
	}

	void removeByShift(size_t at, size_t numToRemove = 1) {
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
