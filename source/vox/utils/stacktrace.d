/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.utils.stacktrace;

import vox.utils;

version(Windows) @nogc nothrow:


void initDbgHelp() @nogc nothrow
{
	SymSetOptions(SymGetOptions() | SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES);

	HANDLE hProcess = GetCurrentProcess();
	SymInitialize(hProcess, null, true);
}

void simpleStackTrace(u32 bottomFramesToSkip = 0, u32 topFramesToSkip = 0) @nogc nothrow {
	// On XP the limit is 63 frames
	enum u32 numFramesToCapture = 63;
	void*[63] trace;
	u16 numFramesCaptured = RtlWalkFrameChain(trace.ptr, numFramesToCapture, 0);
	//writefln("%s %s %s", trace.ptr, numFramesToCapture, numFramesCaptured);
	topFramesToSkip = min(topFramesToSkip, numFramesCaptured);
	if (bottomFramesToSkip > numFramesCaptured-topFramesToSkip) {
		bottomFramesToSkip = numFramesCaptured-topFramesToSkip;
	}
	foreach(frame; trace[topFramesToSkip..numFramesCaptured-bottomFramesToSkip]) {
		writefln("%X", frame);
	}
}

void simpleNamedStackTrace(u32 bottomFramesToSkip = 0, u32 topFramesToSkip = 0) @nogc nothrow {
	// On XP the limit is 63 frames
	enum u32 numFramesToCapture = 63;
	enum MaxNameSize = 1024;
	void*[numFramesToCapture] trace;
	u16 numFramesCaptured = RtlWalkFrameChain(trace.ptr, numFramesToCapture, 0);
	//writefln("%s %s %s", trace.ptr, numFramesToCapture, numFramesCaptured);

	HANDLE hProcess = GetCurrentProcess();

	static struct SymbolBuf {
		align(1):
		SYMBOL_INFO sym;
		char[MaxNameSize] buf = void;
	}

	SymbolBuf symBuf = void;
	symBuf.sym.SizeOfStruct = SYMBOL_INFO.sizeof;
	symBuf.sym.MaxNameLen = MaxNameSize;
	SYMBOL_INFO* symbol = &symBuf.sym;

	topFramesToSkip = min(topFramesToSkip, numFramesCaptured);
	if (bottomFramesToSkip > numFramesCaptured-topFramesToSkip) {
		bottomFramesToSkip = numFramesCaptured-topFramesToSkip;
	}
	// writefln("numFramesCaptured %s", numFramesCaptured);
	foreach(void* pc; trace[topFramesToSkip..numFramesCaptured-bottomFramesToSkip]) {
		u64 displacement;
		if (SymFromAddr(hProcess, cast(u64)pc, &displacement, symbol)) {
			u32 disp;
			IMAGEHLP_LINEA64 line;

			if (SymGetLineFromAddr64(hProcess, cast(u64)pc, &disp, &line)) {
				writefln("- %s at %s:%s:%s", Demangler(symbol.Name.ptr[0..symbol.NameLen]), line.FileName.fromStringz, line.LineNumber, disp);
			} else {
				writefln("- %s", Demangler(symbol.Name.ptr[0..symbol.NameLen]));
			}
		} else {
			writefln("0x%X", pc);
		}
	}
}


struct Result(T) {
	bool success;
	T value;
}

struct Demangler
{
	const(char)[] name;
	void toString(scope SinkDelegate sink) @nogc nothrow const {
		u32 cursor = 0;
		u32 end = cast(u32)name.length;
		u32 idIndex = 0;

		if (name.length <= 2) goto plain;
		if (name[0] != '_') goto plain;
		if (name[1] != 'D') goto plain;

		cursor = 2;

		static u32 decodeNumber(const(char)[] str) {
			u32 res = 0;
			foreach (const(char) c; str) {
				res = res * 10 + (c - '0');
			}
			return res;
		}

		static Result!u32 parseNum(ref u32 cursor, const(char)[] name) {
			u32 start = cursor;
			while(true) {
				if (cursor == name.length) break;
				if (name[cursor] < '0' || name[cursor] > '9') break;
				++cursor;
			}
			if (cursor - start == 0) return Result!u32(false);
			return Result!u32(true, decodeNumber(name[start..cursor]));
		}

		if (name[cursor] < '0' || name[cursor] > '9') goto plain;

		while(true) {
			Result!u32 num = parseNum(cursor, name);
			if (!num.success || cursor+num.value >= end) {
				if (idIndex == 0) goto plain;
				return;
			}
			if (idIndex > 0) sink(".");
			sink(name[cursor..cursor+num.value]);
			cursor += num.value;
			++idIndex;
		}
		return;
		plain: sink(name);
	}
}

void testDemangler()
{
	writefln("%s", Demangler("_D3foo3Foo3barMNgFNjNlNfZNgPv"));
}

void testStackTrace() {
	simpleStackTrace();
	simpleNamedStackTrace();
	//richStackTrace();
	//richestStackTrace();
	// stdout.flush;
	//throw new Exception(null);
}

void stackLimits() {
	void* stackLow;
	void* stackHigh;
	GetCurrentThreadStackLimits(&stackLow, &stackHigh);
	writefln("stack low: 0x%X high: 0x%X", stackLow, stackHigh);
}


/*
void richStackTrace() {
	import std.string : fromStringz;
	import core.demangle : demangle;

	// On XP the limit is 63 frames
	u32 numFramesToCapture = 63;
	enum MaxNameSize = 8*1024;
	void*[63] trace;
	u16 numFramesCaptured = RtlWalkFrameChain(trace.ptr, numFramesToCapture, 0);

	HANDLE hProcess = GetCurrentProcess();

	static struct SymbolBuf {
		align(1):
		SYMBOL_INFO sym;
		char[MaxNameSize] buf = void;
	}

	SymbolBuf symBuf = void;
	symBuf.sym.SizeOfStruct = SYMBOL_INFO.sizeof;
	symBuf.sym.MaxNameLen = MaxNameSize;
	SYMBOL_INFO* symbol = &symBuf.sym;

	writefln("numFramesCaptured %s", numFramesCaptured);
	foreach(void* pc; trace[0..numFramesCaptured])
	{
		u64 displacement;
		if (SymFromAddr(hProcess, cast(u64)pc, &displacement, symbol)) {
			u32 disp;
			IMAGEHLP_LINEA64 line;

			if (SymGetLineFromAddr64(hProcess, cast(u64)pc, &disp, &line)) {
				writefln("0x%X in %s at %s:%s:%s", pc, symbol.Name.ptr[0..symbol.NameLen].demangle, line.FileName.fromStringz, line.LineNumber, disp);
			} else {
				writefln("0x%X in %s", pc, symbol.Name.ptr[0..symbol.NameLen].demangle);
			}
		} else {
			writefln("0x%X", pc);
		}
	}
}

void richestStackTrace() {
	import std.string : fromStringz;
	import core.demangle : demangle;

	// On XP the limit is 63 frames
	u32 numFramesToCapture = 63;
	enum MaxNameSize = 8*1024;
	u64[63] trace;
	char[1024] buf = void;
	u16 numFramesCaptured = RtlWalkFrameChain(cast(void**)trace.ptr, numFramesToCapture, 0);

	HANDLE hProcess = GetCurrentProcess();

	static struct SymbolBuf {
		align(1):
		SYMBOL_INFO sym;
		char[MaxNameSize] buf = void;
	}

	SymbolBuf symBuf = void;
	symBuf.sym.SizeOfStruct = SYMBOL_INFO.sizeof;
	symBuf.sym.MaxNameLen = MaxNameSize;
	SYMBOL_INFO* symbol = &symBuf.sym;

	writefln("numFramesCaptured %s", numFramesCaptured);
	foreach(u64 pc; trace[0..numFramesCaptured])
	{
		u64 displacement;
		u32 inlineNum = SymAddrIncludeInlineTrace(hProcess, pc);
		if (inlineNum) {
			u32 ctx;
			u32 index;
			bool doInline = SymQueryInlineTrace(hProcess, pc, 0, pc, pc, &ctx, &index);
			writefln("inlineNum %s doInline %s context 0x%X index %s", inlineNum, doInline, ctx, index);

			foreach(i; 0..inlineNum)
			{
				const symbolIsValid = SymFromInlineContext(hProcess, pc, ctx, null, symbol);
				if (symbolIsValid) {
					u32 disp;
					IMAGEHLP_LINEA64 line64;

					if (SymGetLineFromInlineContext(hProcess, pc, ctx, 0, &disp, &line64)) {
						writefln("i 0x%X in %s at %s:%s", pc, symbol.Name.ptr[0..symbol.NameLen].demangle, line64.FileName.fromStringz, line64.LineNumber);
					} else {
						writefln("i 0x%X in %s", pc, symbol.Name.ptr[0..symbol.NameLen].demangle);
					}
				} else {
					writefln("i 0x%X", pc);
				}
			}
		}

		const symbolIsValid = SymFromAddr(hProcess, pc, &displacement, symbol);
		if (symbolIsValid) {
			u32 disp;
			IMAGEHLP_LINEA64 line64;

			if (SymGetLineFromAddr64(hProcess, pc, &disp, &line64)) {
				writefln("0x%X in %s at %s:%s", pc, symbol.Name.ptr[0..symbol.NameLen].demangle, line64.FileName.fromStringz, line64.LineNumber);
			} else {
				writefln("0x%X in %s", pc, symbol.Name.ptr[0..symbol.NameLen].demangle);
			}
		} else {
			writefln("0x%X", pc);
		}
	}
}
*/
