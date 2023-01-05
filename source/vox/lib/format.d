/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.format;

import vox.lib;

@nogc nothrow:


alias SinkDelegate = void delegate(scope const(char)[]) @nogc nothrow;

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

void formatPointer(scope SinkDelegate sink, in void* ptr, string fmt) {
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
