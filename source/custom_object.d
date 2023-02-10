module object;

version(Windows) {
	// druntime/src/core/sys/windows/threadaux.d
	extern(C) __gshared int _tls_index;
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

version(DigitalMars)
extern(C) void* _memset32(void* dst, uint val, size_t len) {
	void* dstCopy = dst;
	for (; len > 0; --len) {
		*cast(uint*)dst = val;
		dst += 4;
	}
	return dstCopy;
}

version(DigitalMars)
extern(C) void* _memset64(void* dst, ulong val, size_t len) {
	void* dstCopy = dst;
	for (; len > 0; --len) {
		*cast(ulong*)dst = val;
		dst += 8;
	}
	return dstCopy;
}

version(DigitalMars)
extern(C) void* _memsetn(void* dst, void* val, int len, size_t elemsz) {
	void* dstCopy = dst;
	for (; len; --len) {
		void* src = val;
		for (size_t size = elemsz; size > 0; --size) {
			*cast(ubyte*)dst++ = *cast(ubyte*)src++;
		}
	}
	return dstCopy;
}


alias size_t = typeof(int.sizeof);
alias ptrdiff_t = typeof(cast(void*)0 - cast(void*)0);
alias string = immutable(char)[];
alias noreturn = typeof(*null);

// If this is present with LDC release build we get
// lld-link: error: undefined symbol: _fltused
// >>> referenced by nihlang\bin\testsuite.exe.lto.obj
// https://stackoverflow.com/questions/1583196/building-visual-c-app-that-doesnt-use-crt-functions-still-references-some/1583220#1583220
version(DigitalMars)
extern(C) __gshared int _fltused = 0;



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
