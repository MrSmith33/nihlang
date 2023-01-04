module object;

version(Windows) {
	// druntime/src/core/sys/windows/threadaux.d
	extern (C) __gshared int _tls_index;
}

extern(C) void _d_array_slice_copy(void* dst, size_t dstlen, void* src, size_t srclen, size_t elemsz)
{
	version (LDC) {
		import ldc.intrinsics : llvm_memcpy;
		llvm_memcpy!size_t(dst, src, dstlen * elemsz, 0);
	} else {
		for (size_t size = dstlen * elemsz; size > 0; --size) {
			*cast(ubyte*)dst++ = *cast(ubyte*)src++;
		}
	}
}

alias size_t = typeof(int.sizeof);
alias ptrdiff_t = typeof(cast(void*)0 - cast(void*)0);
alias string = immutable(char)[];


extern(C) int _fltused = 0x9875;



/// Copyright: Copyright Digital Mars 2000 - 2020.
/// License: Distributed under the $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
/// Source: $(DRUNTIMESRC core/internal/_array/_equality.d)
bool __equals(T1, T2)(scope T1[] lhs, scope T2[] rhs) @nogc nothrow pure @trusted
{
	if (lhs.length != rhs.length)
		return false;

	if (lhs.length == 0)
		return true;

	foreach (const i; 0 .. lhs.length) {
		if (at(lhs, i) != at(rhs, i))
			return false;
	}
	return true;
}

pragma(inline, true)
ref at(T)(T[] r, size_t i) @trusted
	// exclude opaque structs due to https://issues.dlang.org/show_bug.cgi?id=20959
	if (!(is(T == struct) && !is(typeof(T.sizeof))))
{
	static if (is(immutable T == immutable void))
		return (cast(ubyte*) r.ptr)[i];
	else
		return r.ptr[i];
}
