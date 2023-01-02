/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.string;

import vox.lib;

@nogc nothrow:


const(char)[] fromStringz(const(char)* cString) {
	if (cString == null) return null;
	const(char)* cursor = cString;
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
