/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.formats.slicer;

import vox.lib;

struct FileDataSlicer
{
	u8[] fileData;
	usz fileCursor = 0;

	// Returns array of Ts of length 'length' stating from fileCursor offset in fileData
	T[] getArrayOf(T)(usz length)
	{
		enforce(fileData.length >= fileCursor + T.sizeof * length, "Not enough bytes in the file");
		auto res = (cast(T*)(fileData.ptr + fileCursor))[0..length];
		fileCursor += T.sizeof * length;
		return res;
	}

	T[] getArrayOfToOffset(T)(usz offset)
	{
		enforce(fileCursor <= offset, "Cannot read to offset. It is behind cursor. Cursor: %s, offset: %s", fileCursor, offset);
		enforce(((offset - fileCursor) % T.sizeof) == 0, "Distance between cursor and offset is not multiple of T.sizeof. Cursor: %s, offset: %s, T.sizeof: %s", fileCursor, offset, T.sizeof);
		auto length = (offset - fileCursor) / T.sizeof;
		auto res = (cast(T*)(fileData.ptr + fileCursor))[0..length];
		fileCursor = offset;
		return res;
	}

	T* getPtrTo(T)() { return getArrayOf!T(1).ptr; }

	T parseBigEndian(T)() {
		u8[T.sizeof] buf = getArrayOf!u8(T.sizeof);
		return bigEndianToNative!T(buf);
	}

	usz offsetOf(T)(T* ptr) {
		enforce(cast(void*)ptr >= fileData.ptr, "Out of bounds");
		enforce(cast(void*)ptr <= fileData.ptr + fileData.length, "Out of bounds");
		return cast(void*)ptr - cast(void*)fileData.ptr;
	}

	usz offsetOf(T)(T[] slice) => offsetOf(slice.ptr);

	void advanceToAlignment(usz alignment) { fileCursor += paddingSize(fileCursor, alignment); }
}
