/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.string;

import vox.lib;

@nogc nothrow:


inout(char)[] fromStringz(inout(char)* cString) {
	if (cString == null) return null;
	inout(char)* cursor = cString;
	while(*cursor) ++cursor;
	usize length = cast(usize)(cursor - cString);
	return cString[0..length];
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

usz parseInt(string str) {
	u32 cursor = 0;
	usz res;
	while ('0' <= str[cursor] && str[cursor] <= '9') {
		if (cursor >= str.length) break;

		res = res * 10 + (str[cursor] - '0');

		++cursor;
	}
	return res;
}

struct LineSizeResult {
	// Equal to input length if no newline found
	// Includes the terminator
	size_t lineLength;
	// Zero if no newline found
	ubyte terminatorLength;
}

LineSizeResult lineSize(const(char)[] input) {
	foreach(i, char c; input) {
		// https://en.wikipedia.org/wiki/Newline#Unicode
		// LF:    Line Feed, U+000A
		// VT:    Vertical Tab, U+000B
		// FF:    Form Feed, U+000C
		// CR:    Carriage Return, U+000D
		// CR+LF: CR (U+000D) followed by LF (U+000A)
		// NEL:   Next Line, U+0085            (UTF-8: C2 85)
		// LS:    Line Separator, U+2028       (UTF-8: E2 80 A8)
		// PS:    Paragraph Separator, U+2029  (UTF-8: E2 80 A9)
		switch (c) {
			case '\r':
				if (i + 1 < input.length && input[i + 1] == '\n') {
					return LineSizeResult(i+2, 2); // CR+LF
				}
				goto case '\n';

			case '\v', '\f', '\n':
				return LineSizeResult(i+1, 1); // LF VT FF CR

			case 0xC2:
				if (i + 1 < input.length && input[i + 1] == 0x85) {
					return LineSizeResult(i+2, 2); // NEL
				}
				goto default;

			case 0xE2:
				if (i + 2 < input.length &&
					input[i + 1] == 0x80 &&
				   (input[i + 2] == 0xA8 || input[i + 2] == 0xA9)) {
					return LineSizeResult(i+2, 2); // NEL
				}
				goto default;

			default: break;
		}
	}

	return LineSizeResult(input.length, 0);
}

unittest {
	assert(lineSize("") == LineSizeResult(0, 0));
	assert(lineSize("a") == LineSizeResult(1, 0));
	assert(lineSize("ab") == LineSizeResult(2, 0));
	assert(lineSize("\r") == LineSizeResult(1, 1));
	assert(lineSize("\n") == LineSizeResult(1, 1));
	assert(lineSize("\v") == LineSizeResult(1, 1));
	assert(lineSize("\f") == LineSizeResult(1, 1));
	assert(lineSize("\u0085") == LineSizeResult(2, 2));
	assert(lineSize("\u2028") == LineSizeResult(2, 2));
	assert(lineSize("\u2029") == LineSizeResult(2, 2));
	assert(lineSize("\xC2") == LineSizeResult(1, 0));
	assert(lineSize("\xE2") == LineSizeResult(1, 0));
	assert(lineSize("\xE2\x80") == LineSizeResult(2, 0));
}

inout(char)[] asciiStripLeft(inout(char)[] input) {
	// ASCII optimization for dynamic arrays.
	size_t i = 0;
	size_t end = input.length;
	while(i < end) {
		auto c = input[i];
		if (!asciiIsWhite(c)) break;
		++i;
	}
	input = input[i .. $];
	return input;
}

bool asciiIsWhite(dchar c) {
	return c == ' ' || (c >= 0x09 && c <= 0x0D);
}
