/// Copyright: Copyright (c) 2026 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.source.identifier;

import vox.lib;
import vox.lib.mem.arena : Arena;

struct Name {
	@nogc nothrow:

	u32 index;
	enum uint HIGH_BIT = 0x8000_0000;

	bool isDefined() => index != 0;
	bool isUndefined() => index == 0;

	size_t toHash() => int32_hash(index);
}

struct NameMap {
	@nogc nothrow:

	Arena!char stringDataBuffer;
	Arena!NameMapEntry entries;
	HashMap!(StringKey, uint, StringKey.init) map;
	HashMap!(FullyQualifiedName, uint, FullyQualifiedName.init) fqnMap;

	Name getOrReg(ref Allocator allocator, const(char)[] str) {
		assert(str.length > 0);
		assert(str.length <= uint.max);

		auto key = StringKey(str);
		uint id = map.get(key, 0);

		if (id == 0) {
			auto start = stringDataBuffer.length;
			char[] buf = stringDataBuffer.put(str);
			auto end = stringDataBuffer.length;

			auto len = cast(uint)(end-start);
			assert(len > 0);
			assert(len <= uint.max);

			key.ptr = buf.ptr; // set new ptr so that buf data is always used for compare

			// can use lower 31 bits
			assert(entries.length < Name.HIGH_BIT, "Id map overflow");
			id = cast(uint)entries.length;
			map.put(allocator, key, id);
			entries.put(NameMapEntry(NameMapString(cast(uint)start, len)));
		}

		return Name(id);
	}
}

private struct StringKey {
	@nogc nothrow:

	// make StringKey POT
	align(8)
	const(char)* ptr;
	uint length;
	uint hash;

	this(const(char)[] str) {
		ptr = str.ptr;
		length = cast(uint)str.length;
		hash = fnv1a_32(cast(const(ubyte)[])str);
	}

	string data() const {
		return cast(string)ptr[0..length];
	}

	bool opEquals(StringKey other) const {
		if (hash != other.hash) return false;
		return this.data == other.data;
	}

	size_t toHash() {
		return hash;
	}
}

private struct NameMapString {
	uint offset;
	uint length;
}

struct FullyQualifiedName {
	@nogc nothrow:

	Name parentId;
	Name id;

	size_t toHash() {
		return cast(size_t)hash_u64((cast(u64)parentId.index << 32) | id.index);
	}
}

private union NameMapEntry {
	@nogc nothrow:

	NameMapString str;
	FullyQualifiedName fqn;

	this(NameMapString str) { this.str = str; }
	this(FullyQualifiedName fqn) { this.fqn = fqn; }
}
