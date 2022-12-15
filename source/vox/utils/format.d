/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.utils.format;

import vox.utils;

@nogc nothrow:

alias SinkDelegate = void delegate(scope const(char)[]) @nogc nothrow;

void writefln(Args...)(string fmt, Args args) {
	writef(fmt, args);
	writeString("\n");
}

void writef(Args...)(string fmt, Args args) {
	void sink(scope const(char)[] str) @nogc nothrow {
		writeString(str);
	}
	formattedWrite(&sink, fmt, args);
}

void formattedWrite(Args...)(scope SinkDelegate sink, string fmt, Args args) {
	u32 cursor = 0;
	static void writeLiteral(scope SinkDelegate sink, string fmt, ref u32 cursor) @nogc nothrow
	{
		u32 start = cursor;
		while (true)
		{
			if (cursor >= fmt.length)
				break;
			if (fmt[cursor] == '%')
			{
				if (cursor + 1 >= fmt.length)
					panic("Invalid format string. End of string after %%");
				// peek char after %
				if (fmt[cursor + 1] != '%')
					break; // this is a format item
				// consume first % to write it
				++cursor;
				// write literal including first %
				sink(fmt[start .. cursor]);
				// start after second %
				start = cursor + 1;
				// cursor is incremented after if
			}
			++cursor; // skip literal
		}
		if (cursor - start)
			sink(fmt[start .. cursor]);
	}

	static string consumeSpec(u32 argIndex, string fmt, ref u32 cursor) @nogc nothrow
	{
		if (cursor >= fmt.length)
			panic("Invalid format string. Missing %%");
		++cursor; // skip %
		u32 start = cursor;
		// parse format item
		while (true)
		{
			if (cursor >= fmt.length)
				panic("Invalid format string. Format item ended with end of string");
			char c = fmt[cursor];
			++cursor;
			if ('a' <= c && c <= 'z' || 'A' <= c && c <= 'Z')
				break;
		}
		u32 end = cursor;
		return fmt[start .. end];
	}

	foreach (i, arg; args)
	{
		writeLiteral(sink, fmt, cursor);
		string spec = consumeSpec(i, fmt, cursor);
		selectFormatter!(Args[i])(sink, arg, spec);
	}
	writeLiteral(sink, fmt, cursor);
}

void writeln(Args...)(Args args) {
	void sink(scope const(char)[] str) @nogc nothrow {
		writeString(str);
	}
	foreach(i, arg; args) {
		selectFormatter!(Args[i])(&sink, arg, "s");
	}
	writeString("\n");
}

void write(Args...)(Args args) {
	void sink(scope const(char)[] str) {
		writeString(str);
	}
	foreach(i, arg; args) {
		selectFormatter!(Args[i])(&sink, arg, "s");
	}
}

void formatValue(T)(scope SinkDelegate sink, auto ref T val, string fmt) {
	selectFormatter!T(sink, val, fmt);
}

template selectFormatter(T) {
	static if (is(const T == const typeof(null))) {
		alias selectFormatter = formatNull;
	}
	else static if (is(const T == const u8) || is(const T == const u16) || is(const T == const u32) || is(const T == const u64)) {
		alias selectFormatter = format_u64;
	}
	else static if (is(const T == const i8) || is(const T == const i16) || is(const T == const i32) || is(const T == const i64)) {
		alias selectFormatter = format_i64;
	}
	else static if (is(const T == const f32)) {
		alias selectFormatter = format_f32;
	}
	else static if (is(const T == const f64)) {
		alias selectFormatter = format_f64;
	}
	else static if (is(const T : const const(char)[])) {
		alias selectFormatter = formatString;
	}
	else static if (is(const T : const U*, U)) {
		alias selectFormatter = formatPointer;
	}
	else static if (is(const T : const E[], E)) {
		alias selectFormatter = formatArray!T;
	}
	else static if (is(const T == const bool)) {
		alias selectFormatter = formatBool;
	}
	else static if (is(const T == const char)) {
		alias selectFormatter = formatChar;
	}
	else static if (is(const T == const dchar)) {
		alias selectFormatter = formatDchar;
	}
	else static if (is(T == struct)) {
		alias selectFormatter = formatStruct!T;
	}
	else {
		static assert(false, "selectFormatter: " ~ T.stringof);
	}
}

void formatString(scope SinkDelegate sink, scope const(char)[] val, string fmt) {
	sink(val);
}

void formatChar(scope SinkDelegate sink, char val, string fmt) {
	char[1] buf = [val];
	sink(buf);
}
void formatDchar(scope SinkDelegate sink, dchar val, string fmt) {
	char[4] buf;
	u32 size = encode_utf8(buf, val);
	sink(buf[0..size]);
}

void formatArray(T : E[], E)(scope SinkDelegate sink, T val, string fmt) {
	sink("[");
	foreach (i, const ref e; val)
	{
		if (i > 0) sink(", ");
		formatValue(sink, e, "s");
	}
	sink("]");
}

u32 encode_utf8(ref char[4] buf, dchar c) {
	if (c < 0x80) {
		buf[0] = cast(u8)c;
		return 1;
	} else if (c < 0x800) {
		buf[0] = 0xC0 | cast(u8)(c >> 6);
		buf[1] = 0x80 | (c & 0x3f);
		return 2;
	} else if (c < 0x10000) {
		buf[0] = 0xE0 | cast(u8)(c >> 12);
		buf[1] = 0x80 | ((c >> 6) & 0x3F);
		buf[2] = 0x80 | (c & 0x3f);
		return 3;
	} else if (c < 0x110000) {
		buf[0] = 0xF0 | cast(u8)(c >> 18);
		buf[1] = 0x80 | ((c >> 12) & 0x3F);
		buf[2] = 0x80 | ((c >> 6) & 0x3F);
		buf[3] = 0x80 | (c & 0x3f);
		return 4;
	}
	panic("Invalid code point");
}

void formatStruct(T)(scope SinkDelegate sink, ref T val, string fmt)
	if(is(T == struct) && __traits(hasMember, T, "toString"))
{
	val.toString(sink);
}

void formatStruct(T)(scope SinkDelegate sink, ref T val, string fmt)
if(is(T == struct) && !__traits(hasMember, T, "toString"))
{
	sink(T.stringof);
	sink("(");
	foreach (i, const ref member; val.tupleof)
	{
		if (i > 0) sink(", ");
		sink(__traits(identifier, T.tupleof[i]));
		sink(" : ");
		formatValue(sink, member, "s");
	}
	sink(")");
}

void formatNull(scope SinkDelegate sink, typeof(null) val, string fmt) {
	sink("null");
}
void formatBool(scope SinkDelegate sink, bool val, string fmt) {
	if (val) sink("true");
	else sink("false");
}

private enum INT_BUF_SIZE = 66;
private enum FLT_BUF_SIZE = INT_BUF_SIZE*2+1;

void format_i64(scope SinkDelegate sink, i64 i, string fmt) {
	format_i64_impl(sink, i, fmt, true);
}

void format_u64(scope SinkDelegate sink, u64 i, string fmt) {
	format_i64_impl(sink, i, fmt, false);
}

void format_i64_impl(scope SinkDelegate sink, u64 i, string fmt, bool signed) {
	char[INT_BUF_SIZE] buf = void;
	u32 numDigits;

	if (i == 0) {
		buf[$-1] = '0';
		numDigits = 1;
	} else switch (fmt[$-1]) {
		case 'x':
			numDigits = formatHex(buf, i, hexDigitsLower);
			break;
		case 'X':
			numDigits = formatHex(buf, i, hexDigitsUpper);
			break;
		default:
			numDigits = formatDecimal(buf, i, signed);
			break;
	}
	sink(buf[$-numDigits..$]);
}

void format_f32(scope SinkDelegate sink, f32 f, string fmt) {
	char[FLT_BUF_SIZE] buf = void;
	u32 numDigits = formatFloat(buf, f);
	sink(buf[$-numDigits..$]);
}

void format_f64(scope SinkDelegate sink, f64 f, string fmt) {
	char[FLT_BUF_SIZE] buf = void;
	u32 numDigits = formatFloat(buf, f);
	sink(buf[$-numDigits..$]);
}

void formatPointer(scope SinkDelegate sink, void* ptr, string fmt) {
	sink("0x");
	char[INT_BUF_SIZE] buf = void;
	u32 numDigits = formatHex(buf, cast(u64)ptr, hexDigitsUpper);
	sink(buf[$-numDigits..$]);
}

private immutable char[16] hexDigitsLower = "0123456789abcdef";
private immutable char[16] hexDigitsUpper = "0123456789ABCDEF";
private immutable char[19] maxNegative_i64 = "9223372036854775808";

// nonzero
u32 formatHex(ref char[INT_BUF_SIZE] sink, u64 i, ref immutable(char)[16] chars) {
	u32 numDigits = 0;
	while (i) {
		sink[INT_BUF_SIZE - ++numDigits] = chars[i & 0xF];
		i >>= 4;
	}
	return numDigits;
}

u32 formatDecimalUnsigned(ref char[INT_BUF_SIZE] sink, u64 u) {
	u32 numDigits = 0;
	do {
		char c = cast(char)('0' + u % 10);
		sink[INT_BUF_SIZE - ++numDigits] = c;
		u /= 10;
	} while (u != 0);
	return numDigits;
}

u32 formatDecimal(ref char[INT_BUF_SIZE] sink, i64 i, bool signed) {
	u32 numDigits = 0;
	u64 u = i;
	if (signed && i < 0) { u = -i; }
	do {
		char c = cast(char)('0' + u % 10);
		sink[INT_BUF_SIZE - ++numDigits] = c;
		u /= 10;
	} while (u != 0);
	if (signed && i < 0) { sink[INT_BUF_SIZE - ++numDigits] = '-'; }
	return numDigits;
}

enum FP_PRECISION = 6;

u32 formatFloat(ref char[FLT_BUF_SIZE] buf, f64 originalFloat) {
	f64 f = originalFloat;
	if (originalFloat < 0) f = -f;
	i64 ipart = cast(i64)(f + 0.00000001);
	f64 frac = f - ipart;
	if (frac < 0) frac = -frac;

	i64 ndigits = 0;
	i64 nzeroes = -1;

	while (frac - cast(i64)(frac) >= 0.0000001 && frac - cast(i64)(frac) <= 0.9999999 && ndigits < FP_PRECISION) {
		if (cast(i64)(frac) == 0) nzeroes++;
		ndigits++;
		frac *= 10;
	}
	if (frac - cast(i64)(frac) > 0.9999999) frac++;

	auto bufPtr = cast(char[INT_BUF_SIZE]*)(buf.ptr+INT_BUF_SIZE+1);
	u32 numDigits = formatDecimalUnsigned(*bufPtr, cast(u64)(frac));
	while (nzeroes) {
		buf[$ - ++numDigits] = '0';
		--nzeroes;
	}

	buf[$ - ++numDigits] = '.';

	bufPtr = cast(char[INT_BUF_SIZE]*)(buf.ptr+FLT_BUF_SIZE-numDigits-INT_BUF_SIZE);
	numDigits += formatDecimalUnsigned(*bufPtr, ipart);

	if (originalFloat < 0) {
		buf[$ - ++numDigits] = '-';
	}

	return numDigits;
}


void testWrite() @nogc nothrow {
	char[512] buf = void;
	u32 cursor;
	void testSink(scope const(char)[] str) @nogc nothrow {
		buf[cursor..cursor+str.length] = str;
		cursor += str.length;
	}
	void test(Args...)(string expected, string fmt, Args args, string file = __FILE__, int line = __LINE__) {
		cursor = 0;
		formattedWrite(&testSink, fmt, args);
		if (expected != buf[0..cursor]) {
			writefln("\033[1;31m[FAIL]\033[0m %s:%s", file, line);
			writefln("Got:      %s", buf[0 .. cursor]);
			writefln("Expected: %s", expected);
			panic("panic");
		}
	}

	scope(exit) writeln("\033[1;32m[SUCCESS]\033[0m");

	test("c", "%s", 'c');
	test("\xFF", "%s", '\xFF');
	test("\U0000FFFF", "%s", '\U0000FFFF');

	test("hello", "%s", "hello");
	test("18446744073709551615", "%s", u64(-1));
	test("0", "%s", u64(0));
	test("18446744073709551615", "%s", u64(0xFFFF_FFFF_FFFF_FFFF));

	test("-9223372036854775808", "%s", i64(-9223372036854775808));
	test("-1", "%s", i64(-1));
	test("0", "%s", i64(0));
	test("9223372036854775807", "%s", i64(9223372036854775807));

	test("ffffffffffffffff", "%x", u64(0xFFFF_FFFF_FFFF_FFFF));
	test("FFFFFFFFFFFFFFFF", "%X", u64(0xFFFF_FFFF_FFFF_FFFF));

	test("4.5", "%s", 4.5);
	test("1.200000", "%s", 1.2f);

	int* b = cast(int*)0x0F0F_F0FF_F0FF_FFF0;
	test("0xF0FF0FFF0FFFFF0", "%s", b);

	test("true", "%s", true);
	test("false", "%s", false);
	test("null", "%s", null);

	static int[] arr = [1, 2];
	test("[1, 2]", "%s", arr);

	static int[2] arr2 = [1, 2];
	test("[1, 2]", "%s", arr2);

	static struct A {
		i32 a = 42;
		i32 b = 60;
	}

	static struct B	{
		void toString(scope SinkDelegate sink) @nogc nothrow const {
			sink("it's B");
		}
	}
	test("A(a : 42, b : 60)", "%s", A());
	test("it's B", "%s", B());
}
