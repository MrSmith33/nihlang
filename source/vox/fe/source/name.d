/// Copyright: Copyright (c) 2026 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.source.identifier;

import vox.lib;
import vox.lib.mem.arena : Arena;
import vox.fe.source.location : Position;

struct Name {
	@nogc nothrow:

	u32 index;
	enum uint HIGH_BIT = 0x8000_0000;

	uint strIndex() {
		assert(!hasParent);
		return index;
	}
	uint fqnIndex() {
		assert(hasParent);
		return index & ~HIGH_BIT;
	}

	bool isDefined() => index != 0;
	bool isUndefined() => index == 0;
	bool hasParent() => cast(bool)(index & HIGH_BIT);

	size_t toHash() => int32_hash(index);
}

struct NameWithPos {
	Name name;
	Position position;
}

struct NameMap {
	@nogc nothrow:

	Arena!char stringDataBuffer;
	Arena!NameMapEntry entries;
	HashMap!(StringKey, uint, StringKey.init) map;
	HashMap!(FullyQualifiedName, uint, FullyQualifiedName.init) fqnMap;

	string get(Name id) {
		if (id.isDefined) {
			if (id.hasParent) {
				id = entries[id.fqnIndex].fqn.id;
			}
			auto str = entries[id.strIndex].str;
			return cast(string)stringDataBuffer.bufPtr[str.offset..str.offset+str.length];
		}
		return "<undefined id>";
	}

	Result!Name getOrReg(ref Allocator allocator, const(char)[] str) {
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
			auto res = map.put(allocator, key, id);
			if (res.isError) return Result!Name.fromError(res);
			entries.put(NameMapEntry(NameMapString(cast(uint)start, len)));
		}

		return Name(id).Result!Name;
	}

	// internal. Called in VoxContext.initialize()
	Result!void regCommonNames(ref Allocator allocator) {
		import vox.lib;
		assert(entries.length == 0);
		assert(map.length == 0);
		assert(stringDataBuffer.length == 0);

		// Reserve zero entry for undefined Name
		entries.put(NameMapEntry(NameMapString(0, 0)));

		foreach (size_t i, string memberName; __traits(allMembers, CommonIds)) {
			string name = __traits(getAttributes, __traits(getMember, CommonIds, memberName))[0];
			auto res = getOrReg(allocator, name);
			if (res.isError) return Result!void.fromError(res);
			Name got = res.data;
			Name expected = __traits(getMember, CommonIds, memberName);
			enforce(got == expected, "%s %s", got.index, expected.index);
		}
		return Result!void();
	}
}

enum CommonIds : Name {
	// Name.init == Name(0)

	@("i32")      id_i32      = Name(1),
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
