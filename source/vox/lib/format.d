/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

// %s automatic
// %b integer formatted as binary
// %B for binary prefix (only integers, negative integers formatted with positive prefixes)
// %m for metric prefix with u for micro (integers, floats and Duration)
// %M for metric prefix with µ for micro (integers, floats and Duration)
module vox.lib.format;

import vox.lib;

@nogc nothrow:


alias SinkDelegate = void delegate(scope const(char)[]) @nogc nothrow;

void formattedWriteln(Args...)(scope SinkDelegate sink, string fmt, Args args) {
	formattedWrite(sink, fmt, args);
	sink("\n");
}

void formattedWrite(Args...)(scope SinkDelegate sink, string fmt, Args args) {
	u32 cursor = 0;

	foreach (i, arg; args) {
		writeLiteral(sink, fmt, cursor);
		FormatSpec spec = consumeSpec(i, fmt, cursor);
		selectFormatter!(Args[i])(sink, arg, spec);
	}

	writeLiteral(sink, fmt, cursor);
}

void formatValue(T)(scope SinkDelegate sink, const auto ref T val, FormatSpec spec = FormatSpec()) {
	selectFormatter!T(sink, val, spec);
}

private void writeLiteral(scope SinkDelegate sink, string fmt, ref u32 cursor) {
	u32 start = cursor;
	while (true) {
		if (cursor >= fmt.length){
			break;
		}

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

private FormatSpec consumeSpec(u32 argIndex, string fmt, ref u32 cursor) {
	FormatSpec spec;

	if (cursor >= fmt.length) {
		panic("Invalid format string. Missing %%");
	}

	++cursor; // skip %

	if (cursor >= fmt.length) {
		panic("Invalid format string. End of input after %%");
	}

	// flags
	loop: while (true) {
		if (cursor >= fmt.length) {
			panic("Invalid format string. Format item ended with end of string");
		}

		switch(fmt[cursor]) {
			case '-': spec.flags |= FormatSpecFlags.dash;  break;
			case '+': spec.flags |= FormatSpecFlags.plus;  break;
			case '#': spec.flags |= FormatSpecFlags.hash;  break;
			case '0': spec.flags |= FormatSpecFlags.zero;  break;
			case ' ': spec.flags |= FormatSpecFlags.space; break;
			default: break loop;
		}

		++cursor;
	}

	uint width;
	while ('0' <= fmt[cursor] && fmt[cursor] <= '9') {
		if (cursor >= fmt.length) {
			panic("Invalid format string. Format item ended with end of string");
		}

		width = width * 10 + (fmt[cursor] - '0');

		if (width > 64) {
			panic("Invalid format string. Max width is 64");
		}

		++cursor;
	}
	spec.width = cast(ubyte)width;

	// format char
	if (cursor >= fmt.length) {
		panic("Invalid format string. Format item ended with end of string");
	}

	char c = fmt[cursor];
	if ('a' <= c && c <= 'z' || 'A' <= c && c <= 'Z') {
		spec.spec = c;
		++cursor;
	} else {
		panic("Invalid format string. Expected format char at the end. Got `%s`", c);
	}

	return spec;
}

template selectFormatter(T) {
	static if (is(immutable T == immutable typeof(null))) {
		alias selectFormatter = formatNull;
	}
	else static if (is(immutable T == immutable u8) || is(immutable T == immutable u16) || is(immutable T == immutable u32) || is(immutable T == immutable u64)) {
		alias selectFormatter = format_u64;
	}
	else static if (is(immutable T == immutable i8) || is(immutable T == immutable i16) || is(immutable T == immutable i32) || is(immutable T == immutable i64)) {
		alias selectFormatter = format_i64;
	}
	else static if (is(immutable T == immutable f32)) {
		alias selectFormatter = format_f64;
	}
	else static if (is(immutable T == immutable f64)) {
		alias selectFormatter = format_f64;
	}
	else static if (is(immutable T : immutable immutable(char)[])) {
		alias selectFormatter = formatString;
	}
	else static if (is(immutable T : immutable U*, U)) {
		alias selectFormatter = formatPointer;
	}
	else static if (is(typeof(*T) == function)) {
		alias selectFormatter = formatPointer;
	}
	else static if (is(immutable T : immutable E[], E)) {
		alias selectFormatter = formatArray!T;
	}
	else static if (is(immutable T == immutable bool)) {
		alias selectFormatter = formatBool;
	}
	else static if (is(immutable T == immutable char)) {
		alias selectFormatter = formatChar;
	}
	else static if (is(immutable T == immutable dchar)) {
		alias selectFormatter = formatDchar;
	}
	else static if (is(T == struct)) {
		alias selectFormatter = formatStruct!T;
	}
	else static if (is(T U == enum)) {
		alias selectFormatter = selectFormatter!U;
	}
	else {
		static assert(false, "selectFormatter: " ~ T.stringof);
	}
}

struct EscapedString {
	@nogc nothrow:
	const(char)[] data;
	void toString(scope SinkDelegate sink, FormatSpec spec) const @nogc nothrow {
		u32 start;
		u32 end;
		foreach (i, char c; data) {
			if (c < 32 || c > 126) {
				if (end > start) {
					sink(data[start..end]);
				}
				formattedWrite(sink, "\\x%X", cast(u8)c);
				start = cast(u32)i+1;
				end = cast(u32)i+1;
			} else {
				end = cast(u32)i+1;
			}
		}
		if (end > start) {
			sink(data[start..end]);
		}
	}
}

void formatString(scope SinkDelegate sink, scope const(char)[] val, FormatSpec spec) {
	sink(val);
}

void formatChar(scope SinkDelegate sink, char val, FormatSpec spec) {
	char[1] buf = [val];
	sink(buf);
}
void formatDchar(scope SinkDelegate sink, dchar val, FormatSpec spec) {
	char[4] buf;
	u32 size = encode_utf8(buf, val);
	sink(buf[0..size]);
}

void formatArray(T : E[], E)(scope SinkDelegate sink, scope const T val, FormatSpec spec) {
	sink("[");
	foreach (i, const ref e; val)
	{
		if (i > 0) sink(", ");
		formatValue(sink, e);
	}
	sink("]");
}

void formatStruct(T)(scope SinkDelegate sink, scope const ref T val, FormatSpec spec)
	if(is(T == struct) && __traits(hasMember, T, "toString"))
{
	val.toString(sink, spec);
}

void formatStruct(T)(scope SinkDelegate sink, scope const ref T val, FormatSpec spec)
if(is(T == struct) && !__traits(hasMember, T, "toString"))
{
	sink(T.stringof);
	sink("(");
	foreach (i, const ref member; val.tupleof)
	{
		if (i > 0) sink(", ");
		sink(__traits(identifier, T.tupleof[i]));
		sink(" : ");
		formatValue(sink, member);
	}
	sink(")");
}

void formatNull(scope SinkDelegate sink, typeof(null) val, FormatSpec spec) {
	sink("null");
}

void formatBool(scope SinkDelegate sink, bool val, FormatSpec spec) {
	if (val) sink("true");
	else sink("false");
}

private enum INT_BUF_SIZE = 66;
// Enough space to format 2 ints and dot
private enum FMT_BUF_SIZE = INT_BUF_SIZE*2+1;

void format_i64(scope SinkDelegate sink, i64 i, FormatSpec spec = FormatSpec()) {
	format_i64_impl(sink, i, spec, true);
}

void format_u64(scope SinkDelegate sink, u64 i, FormatSpec spec) {
	format_i64_impl(sink, i, spec, false);
}

void format_i64_impl(scope SinkDelegate sink, u64 i, FormatSpec spec, bool signed) {
	char[FMT_BUF_SIZE] buf = void;
	u32 numDigits;

	char padding = ' ';
	bool minus = signed && (cast(i64)i < 0);

	if (minus) i = -i;

	if (spec.hasSpace) padding = ' ';
	if (spec.hasZero) padding = '0';

	if (i == 0) {
		buf[$-1] = '0';
		numDigits = 1;
	} else switch (spec.spec) {
		case 'b':
			numDigits = formatBinaryBase(buf, i);
			break;
		case 'x':
			numDigits = formatHex(buf, i, hexDigitsLower);
			break;
		case 'X':
			numDigits = formatHex(buf, i, hexDigitsUpper);
			break;
		case 'm':
		case 'M':
			auto dec = calcScaledDecimal(i);
			formatMetricPrefix(buf, numDigits, dec.prefix, false);
			formatScaledDecimal(buf, numDigits, dec);
			break;
		case 'B':
			auto bin = calcScaledBinary(i);
			formatBinaryPrefix(buf, numDigits, bin.prefix);
			formatScaledDecimal(buf, numDigits, bin);
			break;
		default:
			numDigits = formatDecimal(buf, i, signed);
			break;
	}

	if (minus) buf[$ - ++numDigits] = '-';

	while (spec.width > numDigits) {
		buf[$ - ++numDigits] = padding;
	}

	sink(buf[$-numDigits..$]);
}

void format_f64(scope SinkDelegate sink, f64 f, FormatSpec spec = FormatSpec()) {
	char[FMT_BUF_SIZE] buf = void;
	u32 numDigits = 0;

	bool minus = f < 0;
	if (minus) f = -f;

	switch (spec.spec) {
		case 'm':
		case 'M':
			auto dec = calcScaledDecimal(f);
			formatMetricPrefix(buf, numDigits, dec.prefix, spec.spec == 'M');
			formatScaledDecimal(buf, numDigits, dec);
			break;
		default:
			formatFloat(buf, numDigits, f);
			break;
	}

	if (minus) buf[$ - ++numDigits] = '-';

	sink(buf[$-numDigits..$]);
}

void formatPointer(scope SinkDelegate sink, in void* ptr, FormatSpec spec) {
	if (ptr is null) {
		sink("null");
		return;
	}
	sink("0x");
	char[FMT_BUF_SIZE] buf = void;
	u32 numDigits = formatHex(buf, cast(u64)ptr, hexDigitsUpper);
	sink(buf[$-numDigits..$]);
}

private immutable char[16] hexDigitsLower = "0123456789abcdef";
private immutable char[16] hexDigitsUpper = "0123456789ABCDEF";

// nonzero
u32 formatHex(ref char[FMT_BUF_SIZE] sink, u64 i, ref immutable(char)[16] chars) {
	u32 numDigits = 0;
	while (i) {
		sink[$ - ++numDigits] = chars[i & 0xF];
		i >>= 4;
	}
	return numDigits;
}

// nonzero
u32 formatBinaryBase(ref char[FMT_BUF_SIZE] sink, u64 u) {
	u32 numDigits = 0;
	do {
		char c = cast(char)('0' + (u & 1));
		sink[$ - ++numDigits] = c;
		u >>= 1;
	} while (u != 0);
	return numDigits;
}

void formatDecimalUnsigned(ref char[FMT_BUF_SIZE] sink, ref u32 numDigits, u64 u) {
	do {
		char c = cast(char)('0' + (u % 10));
		sink[$ - ++numDigits] = c;
		u /= 10;
	} while (u != 0);
}

u32 formatDecimal(ref char[FMT_BUF_SIZE] buf, i64 i, bool signed) {
	u32 numDigits = 0;
	u64 u = i;
	if (signed && i < 0) { u = -i; }
	do {
		char c = cast(char)('0' + (u % 10));
		buf[$ - ++numDigits] = c;
		u /= 10;
	} while (u != 0);
	if (signed && i < 0) { buf[$ - ++numDigits] = '-'; }
	return numDigits;
}

struct ScaledDecimal {
	// 3-4 decimal digits or 0
	u32 whole;
	// 0-2
	u8 fractionDigits;
	// 0-6 (10^[0;30]) for u64
	// -10 - 102 (10^[-30;306]) for f64
	i8 prefix;
}

ScaledDecimal calcScaledDecimal(T)(T value)
	if (is(T == u64) || is(T == f64))
{
	if (value == 0) return ScaledDecimal(cast(u32)value, 0, 0);

	i32 power = 0;

	// Bring any value to 4 digits
	while(value < 1000) {
		value *= 10;
		power -= 1;
	}
	while(value >= 10000) {
		value /= 10;
		power += 1;
	}

	// Round to 3 digits
	value = divNear(value, 10); // round to even
	power += 3;

	// Rounding may have produced 4th digit
	if (value >= 1000) {
		value /= 10;
		power += 1;
	}

	const u32 fractionDigits = 2 - modEuclidean(power, 3);
	const i32 prefix = divFloor(power, 3);

	// too small
	if (prefix < -10) return ScaledDecimal(0, 0, 0);

	return ScaledDecimal(cast(u32)value, cast(u8)fractionDigits, cast(i8)prefix);
}

ScaledDecimal calcScaledBinary(u64 value) {
	if (value == 0) return ScaledDecimal(cast(u32)value, 0);

	// max is 63, for u64
	i32 power = bsr(value);

	// max is 6
	const i32 prefix = divFloor(power, 10);
	assert(prefix >= 0);
	power = prefix * 10;

	// Produces 4-7 digits
	// branch select ordering to avoid overflow/underflow
	if (value < (u64.max / 1000))
		value = (value * 1000) >> power;
	else
		value = (value >> power) * 1000;

	// Round to 3-5 digits
	u32 fractionDigits = 0;
	if (value >= 99950) {
		// Cut off 3 digits, to get 3-4 digits
		value = divNear(value, 1000);
		fractionDigits = 0;
	} else if (value >= 9950) {
		// Cut off 2 digits, to get 3-4 digits
		value = divNear(value, 100);
		fractionDigits = 1;
	} else {
		// Cut off 1 digit, to get 3-4 digits
		value = divNear(value, 10);
		fractionDigits = 2;
	}

	return ScaledDecimal(cast(u32)value, cast(u8)fractionDigits, cast(i8)prefix);
}

void formatMetricPrefix(ref char[FMT_BUF_SIZE] buf, ref u32 numDigits, const i8 prefix, const bool useGreek) {
	if (prefix == 0) return;

	// print with scientific notation
	if (prefix > 10) {
		formatDecimalUnsigned(buf, numDigits, cast(u64)prefix * 3);
		buf[$ - ++numDigits] = '+';
		buf[$ - ++numDigits] = 'e';
		return;
	}

	if (useGreek && prefix == -2) { // μ
		buf[$ - ++numDigits] = 0xBC;
		buf[$ - ++numDigits] = 0xCE;
	} else {
		buf[$ - ++numDigits] = metrixPrefixesAscii[10 + prefix];
	}
}

void formatBinaryPrefix(ref char[FMT_BUF_SIZE] buf, ref u32 numDigits, const i8 prefix) {
	assert(prefix >= 0 && prefix <= 10);
	if (prefix == 0) return;
	buf[$ - ++numDigits] = 'i';
	buf[$ - ++numDigits] = binaryPrefixes[prefix];
}

void formatDecimalFraction(ref char[FMT_BUF_SIZE] buf, ref u32 numDigits, ref u32 value, bool skipTrailingZeroes, u8 fractionDigits) {
	switch (fractionDigits) {
		case 2:
			if (skipTrailingZeroes && value % 100 == 0) {
				value /= 100;
				break;
			}
			buf[$ - ++numDigits] = cast(char)('0' + value % 10);
			value /= 10;
			buf[$ - ++numDigits] = cast(char)('0' + value % 10);
			value /= 10;
			buf[$ - ++numDigits] = '.';
			break;
		case 1:
			if (skipTrailingZeroes && value % 100 == 0) {
				value /= 10;
				break;
			}
			buf[$ - ++numDigits] = cast(char)('0' + value % 10);
			value /= 10;
			buf[$ - ++numDigits] = '.';
			break;
		default:
			break;
	}
}

void formatScaledDecimal(ref char[FMT_BUF_SIZE] buf, ref u32 numDigits, const ScaledDecimal dec) {
	// print fractional part
	u32 value = dec.whole;
	const bool skipTrailingZeroes = dec.prefix == 0;
	formatDecimalFraction(buf, numDigits, value, skipTrailingZeroes, dec.fractionDigits);

	// print whole part
	do {
		char c = cast(char)('0' + (value % 10));
		buf[$ - ++numDigits] = c;
		value /= 10;
	} while (value != 0);
}

enum FP_PRECISION = 6;

u32 formatFloat(ref char[FMT_BUF_SIZE] buf, ref u32 numDigits, f64 originalFloat) {
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
	if (nzeroes < 0) nzeroes = 0;

	if (frac - cast(i64)(frac) > 0.9999999) frac++;

	// decimal after dot
	formatDecimalUnsigned(buf, numDigits, cast(u64)(frac));
	while (nzeroes) {
		buf[$ - ++numDigits] = '0';
		--nzeroes;
	}

	buf[$ - ++numDigits] = '.';
	formatDecimalUnsigned(buf, numDigits, ipart);

	if (originalFloat < 0) {
		buf[$ - ++numDigits] = '-';
	}

	return numDigits;
}

struct FormatSpec {
	nothrow @nogc:

	char spec = 's';
	ubyte width;
	ubyte flags;
	ubyte pad;

	bool hasDash()  { return cast(bool)(flags & FormatSpecFlags.dash); }
	bool hasZero()  { return cast(bool)(flags & FormatSpecFlags.zero); }
	bool hasSpace() { return cast(bool)(flags & FormatSpecFlags.space); }
	bool hasPlus()  { return cast(bool)(flags & FormatSpecFlags.plus); }
	bool hasHash()  { return cast(bool)(flags & FormatSpecFlags.hash); }
}

enum FormatSpecFlags : ubyte {
	dash   = 1 << 0,
	zero   = 1 << 1,
	space  = 1 << 2,
	plus   = 1 << 3,
	hash   = 1 << 4,
}


// -30 .. 30, with step of 3. Or -10 to 10 with step of 1
immutable(char[21]) metrixPrefixesAscii = "qryzafpnum kMGTPEZYRQ";
immutable(char[11]) binaryPrefixes = " KMGTPEZYRQ";

void testFormatting() {
	char[512] buf = void;
	u32 cursor;
	void testSink(scope const(char)[] str) @nogc nothrow {
		buf[cursor..cursor+str.length] = str;
		cursor += str.length;
	}
	void test(Args...)(string expected, string fmt, Args args, string file = __FILE__, int line = __LINE__) @nogc nothrow {
		cursor = 0;
		formattedWrite(&testSink, fmt, args);
		//writefln(fmt, args);
		if (expected != buf[0..cursor]) {
			writefln("\033[1;31m[FAIL]\033[0m %s:%s", file, line);
			writefln("Got:      %s", buf[0 .. cursor]);
			writefln("Expected: %s", expected);
			panic("panic");
		}
	}

	scope(exit) writeln("\033[1;32m[SUCCESS]\033[0m");

	// space, zero, width
	test("0010", "%04x", u64(16));
	test("  10", "% 4x", u64(16));
	test("  10", "%4x",  u64(16));

	test("0011", "%04b", u64(3));
	test("  11", "% 4b", u64(3));
	test("  11", "%4b",  u64(3));


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

	static if (size_t.sizeof == 8) {
		int* b = cast(int*)0x0F0F_F0FF_F0FF_FFF0;
		test("0xF0FF0FFF0FFFFF0", "%s", b);
	} else {
		int* b = cast(int*)0xF0FF_FFF0;
		test("0xF0FFFFF0", "%s", b);
	}

	test("true", "%s", true);
	test("false", "%s", false);
	test("null", "%s", null);

	static immutable int[] arr = [1, 2];
	test("[1, 2]", "%s", arr);

	int[2] arr2 = [1, 2];
	test("[1, 2]", "%s", arr2);

	static struct A {
		i32 a = 42;
		i32 b = 60;
	}

	static struct B	{
		void toString(scope SinkDelegate sink, FormatSpec spec) @nogc nothrow const {
			sink("it's B");
		}
	}
	test("A(a : 42, b : 60)", "%s", A());
	test("it's B", "%s", B());
}

void testFormatting2() {
	char[512] buf = void;
	u32 cursor;
	void testSink(scope const(char)[] str) @nogc nothrow {
		buf[cursor..cursor+str.length] = str;
		cursor += str.length;
	}

	void test(T)(string fmt, T num, string expected, string file = __MODULE__, int line = __LINE__) {
		cursor = 0;
		formattedWrite(&testSink, fmt, num);

		if (expected != buf[0..cursor]) {
			writefln("\033[1;31m[FAIL]\033[0m %s:%s", file, line);
			writefln("Got:      %s", buf[0 .. cursor]);
			writefln("Expected: %s", expected);
			panic(line, file, 1, "panic");
		}
	}

	test("%m", -10_000_000_000_000_000_000_000_000_000_000_000.0, "-10.0e+33");
	test("%m", -1_000_000_000_000_000_000_000_000_000_000_000.0, "-1.00e+33");
	test("%m", -100_000_000_000_000_000_000_000_000_000_000.0, "-100Q");
	test("%m", -10_000_000_000_000_000_000_000_000_000_000.0, "-10.0Q");
	test("%m", -1_000_000_000_000_000_000_000_000_000_000.0, "-1.00Q");
	test("%m", -100_000_000_000_000_000_000_000_000_000.0, "-100R");
	test("%m", -10_000_000_000_000_000_000_000_000_000.0, "-10.0R");
	test("%m", -1_000_000_000_000_000_000_000_000_000.0, "-1.00R");
	test("%m", -100_000_000_000_000_000_000_000_000.0, "-100Y");
	test("%m", -10_000_000_000_000_000_000_000_000.0, "-10.0Y");
	test("%m", -1_000_000_000_000_000_000_000_000.0, "-1.00Y");
	test("%m", -100_000_000_000_000_000_000_000.0, "-100Z");
	test("%m", -10_000_000_000_000_000_000_000.0, "-10.0Z");
	test("%m", -1_000_000_000_000_000_000_000.0, "-1.00Z");
	test("%m", -100_000_000_000_000_000_000.0, "-100E");
	test("%m", -10_000_000_000_000_000_000.0, "-10.0E");

	test("%m", long.min, "-9.22E");
	test("%m", -9_223_372_036_854_775_807, "-9.22E");
	test("%m", -1_000_000_000_000_000_000, "-1.00E");
	test("%m", -100_000_000_000_000_000, "-100P");
	test("%m", -10_000_000_000_000_000, "-10.0P");
	test("%m", -1_000_000_000_000_000, "-1.00P");
	test("%m", -100_000_000_000_000, "-100T");
	test("%m", -10_000_000_000_000, "-10.0T");
	test("%m", -1_000_000_000_000, "-1.00T");
	test("%m", -100_000_000_000, "-100G");
	test("%m", -10_000_000_000, "-10.0G");
	test("%m", -1_000_000_000, "-1.00G");
	test("%m", -100_000_000, "-100M");
	test("%m", -10_000_000, "-10.0M");
	test("%m", -1_000_000, "-1.00M");
	test("%m", -100_000, "-100k");
	test("%m", -10_000, "-10.0k");
	test("%m", -1_000, "-1.00k");
	test("%m", -100, "-100");
	test("%m", -10, "-10");
	test("%m", -1, "-1");
	test("%m", 0, "0");
	test("%m", 1, "1");
	test("%m", 10, "10");
	test("%m", 100, "100");
	test("%m", 1_000, "1.00k");
	test("%m", 10_000, "10.0k");
	test("%m", 100_000, "100k");
	test("%m", 1_000_000, "1.00M");
	test("%m", 10_000_000, "10.0M");
	test("%m", 100_000_000, "100M");
	test("%m", 1_000_000_000, "1.00G");
	test("%m", 10_000_000_000, "10.0G");
	test("%m", 100_000_000_000, "100G");
	test("%m", 1_000_000_000_000, "1.00T");
	test("%m", 10_000_000_000_000, "10.0T");
	test("%m", 100_000_000_000_000, "100T");
	test("%m", 1_000_000_000_000_000, "1.00P");
	test("%m", 10_000_000_000_000_000, "10.0P");
	test("%m", 100_000_000_000_000_000, "100P");
	test("%m", 1_000_000_000_000_000_000, "1.00E");
	test("%m", ulong.max, "18.4E");

	test("%m", 10_000_000_000_000_000_000.0, "10.0E");
	test("%m", 100_000_000_000_000_000_000.0, "100E");
	test("%m", 1_000_000_000_000_000_000_000.0, "1.00Z");
	test("%m", 10_000_000_000_000_000_000_000.0, "10.0Z");
	test("%m", 100_000_000_000_000_000_000_000.0, "100Z");
	test("%m", 1_000_000_000_000_000_000_000_000.0, "1.00Y");
	test("%m", 10_000_000_000_000_000_000_000_000.0, "10.0Y");
	test("%m", 100_000_000_000_000_000_000_000_000.0, "100Y");
	test("%m", 1_000_000_000_000_000_000_000_000_000.0, "1.00R");
	test("%m", 10_000_000_000_000_000_000_000_000_000.0, "10.0R");
	test("%m", 100_000_000_000_000_000_000_000_000_000.0, "100R");
	test("%m", 1_000_000_000_000_000_000_000_000_000_000.0, "1.00Q");
	test("%m", 10_000_000_000_000_000_000_000_000_000_000.0, "10.0Q");
	test("%m", 100_000_000_000_000_000_000_000_000_000_000.0, "100Q");
	test("%m", 10e31, "100Q");
	test("%m", 1_000_000_000_000_000_000_000_000_000_000_000.0, "1.00e+33");
	test("%m", 10_000_000_000_000_000_000_000_000_000_000_000.0, "10.0e+33");

	test("%m", 0x1p-1022, "0");
	test("%m", f64.max, "180e+306");

	// numbers less than 1.0 or close to 1
	test("%m", 1.234, "1.23");
	test("%m", 1.000, "1");
	test("%m", 0.9994, "999m");
	test("%m", 0.9995, "1");
	test("%m", 0.9996, "1");
	test("%m", 0.1234, "123m");
	test("%m", 0.01234, "12.3m");
	test("%m", 0.001234, "1.23m");
	test("%m", 0.0001234, "123u");
	test("%M", 0.0001234, "123μ");

	test("%m", -1.234, "-1.23");
	test("%m", -1.000, "-1");
	test("%m", -0.9994, "-999m");
	test("%m", -0.9995, "-1");
	test("%m", -0.9996, "-1");
	test("%m", -0.1234, "-123m");
	test("%m", -0.01234, "-12.3m");
	test("%m", -0.001234, "-1.23m");
	test("%m", -0.0001234, "-123u");

	test("%m", 1e-1,  "100m");
	test("%m", 1e-2,  "10.0m");
	test("%m", 1e-3,  "1.00m");
	test("%m", 1e-4,  "100u");
	test("%m", 1e-5,  "10.0u");
	test("%m", 1e-6,  "1.00u");
	test("%m", 1e-7,  "100n");
	test("%m", 1e-8,  "10.0n");
	test("%m", 1e-9,  "1.00n");
	test("%m", 1e-10, "100p");
	test("%m", 1e-11, "10.0p");
	test("%m", 1e-12, "1.00p");
	test("%m", 1e-13, "100f");
	test("%m", 1e-14, "10.0f");
	test("%m", 1e-15, "1.00f");
	test("%m", 1e-16, "100a");
	test("%m", 1e-17, "10.0a");
	test("%m", 1e-18, "1.00a");
	test("%m", 1e-19, "100z");
	test("%m", 1e-20, "10.0z");
	test("%m", 1e-21, "1.00z");
	test("%m", 1e-22, "100y");
	test("%m", 1e-23, "10.0y");
	test("%m", 1e-24, "1.00y");
	test("%m", 1e-25, "100r");
	test("%m", 1e-26, "10.0r");
	test("%m", 1e-27, "1.00r");
	test("%m", 1e-28, "100q");
	test("%m", 1e-29, "10.0q");
	test("%m", 1e-30, "1.00q");
	test("%m", 1e-31, "0");
	test("%m", 1e-32, "0");
	test("%m", 1e-33, "0");

	// binary
	test("%B", 0, "0");
	test("%B", 1, "1");
	test("%B", 10, "10");
	test("%B", 100, "100");
	test("%B", 999, "999");
	test("%B", 1_000, "1000");
	test("%B", 1_023, "1023");
	test("%B", 1_024, "1.00Ki");
	test("%B", 10_000, "9.77Ki");
	test("%B", 100_000, "97.7Ki");
	test("%B", 1_000_000, "977Ki");
	test("%B", 10_000_000, "9.54Mi");
	test("%B", 100_000_000, "95.4Mi");
	test("%B", 1_000_000_000, "954Mi");
	test("%B", 10_000_000_000, "9.31Gi");
	test("%B", 100_000_000_000, "93.1Gi");
	test("%B", 1_000_000_000_000, "931Gi");
	test("%B", 10_000_000_000_000, "9.09Ti");
	test("%B", 100_000_000_000_000, "90.9Ti");
	test("%B", 1_000_000_000_000_000, "909Ti");
	test("%B", 10_000_000_000_000_000, "8.88Pi");
	test("%B", 100_000_000_000_000_000, "88.0Pi");
	test("%B", 1_000_000_000_000_000_000, "888Pi");
	test("%B", u64.max, "15.0Ei");
	test("%B", i64.min, "-8.00Ei");
	test("%B", i64.max, "7.00Ei");
}
