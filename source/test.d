/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module test;

//@nogc nothrow:

import std.stdio;
import vox.utils;

version(all) {
}

version(D_BetterC) {
	pragma(linkerDirective, "-L/nodefaultlib:libcmt -L/nodefaultlib:libvcruntime -L/nodefaultlib:oldnames -L/machine:x64 -L/subsystem:console -L/debug -L/entry:main");
	extern(C) void _assert(const(char)* msg, const(char)* file, uint line) {
		ExitProcess(1);
	}
}

extern(Windows) noreturn ExitProcess(uint uExitCode);
extern(Windows) void* GetStdHandle(u32 nStdHandle);
extern(Windows) bool WriteFile(
	void* hFile,
	u8* lpBuffer,
	u32 nNumberOfCharsToWrite,
	u32* lpNumberOfCharsWritten,
	void* lpOverlapped
);
extern(Windows) void* LoadLibraryA(const(char)* lpLibFileName);
extern(Windows) void* GetProcAddress(void* hModule, const(char)* lpProcName);

struct RUNTIME_FUNCTION {
	u32 BeginAddress;
	u32 EndAddress;
	union {
		u32 UnwindInfoAddress;
		u32 UnwindData;
	}
}

struct UNWIND_HISTORY_TABLE
{
	u64 ImageBase;
	RUNTIME_FUNCTION* FunctionEntry;
}

extern(Windows) bool RtlAddFunctionTable(
	RUNTIME_FUNCTION* FunctionTable,
	u32 EntryCount,
	u64 BaseAddress
);

extern(Windows) RUNTIME_FUNCTION* RtlLookupFunctionEntry(
	u64                   ControlPc,
	u64*                  ImageBase,
	UNWIND_HISTORY_TABLE* HistoryTable
);

enum u32 STD_INPUT_HANDLE  = 0xFFFFFFF6;
enum u32 STD_OUTPUT_HANDLE = 0xFFFFFFF5;
enum u32 STD_ERROR_HANDLE  = 0xFFFFFFF4;

//extern(Windows) bool StackWalk(
//	DWORD MachineType,
//	HANDLE hProcess,
//	HANDLE hThread,
//	LPSTACKFRAME StackFrame,
//	LPVOID ContextRecord,
//	PREAD_PROCESS_MEMORY_ROUTINE ReadMemoryRoutine,
//	PFUNCTION_TABLE_ACCESS_ROUTINE FunctionTableAccessRoutine,
//	PGET_MODULE_BASE_ROUTINE GetModuleBaseRoutine,
//	PTRANSLATE_ADDRESS_ROUTINE TranslateAddress);



struct ThreadState {

}

isize global;

struct Arena {

}

void printString(string str) {
	void* handle = GetStdHandle(STD_OUTPUT_HANDLE);
	//SetConsoleOutputCP(65001);
	u32 numWritten;
	WriteFile(
		handle,
		cast(u8*)str.ptr,
		cast(u32)str.length,
		&numWritten,
		null);
}


void main(string[] args)
{
	//testStackTrace;


}

const char[2][100] digits = [
    "00", "01", "02", "03", "04", "05", "06", "07", "08", "09",
    "10", "11", "12", "13", "14", "15", "16", "17", "18", "19",
    "20", "21", "22", "23", "24", "25", "26", "27", "28", "29",
    "30", "31", "32", "33", "34", "35", "36", "37", "38", "39",
    "40", "41", "42", "43", "44", "45", "46", "47", "48", "49",
    "50", "51", "52", "53", "54", "55", "56", "57", "58", "59",
    "60", "61", "62", "63", "64", "65", "66", "67", "68", "69",
    "70", "71", "72", "73", "74", "75", "76", "77", "78", "79",
    "80", "81", "82", "83", "84", "85", "86", "87", "88", "89",
    "90", "91", "92", "93", "94", "95", "96", "97", "98", "99"
];

void write_uint(scope void delegate(const(char[])) sink, u64 u) {
    if (u == 0) return sink("0");
    u32 c = 0;
    u32 d = 0;
    u32 power = 1;
    while (power <= u) {
    	power *= 10;
    	++c;
    }
    d = c;
    while (c >= 2) {
        *cast(u16*)(io.buf + io.end + c - 2) = *cast(u16*)(digits[u % 100]);
        u /= 100;
        c -= 2;
    }
    if (c) io.buf[io.end + c - 1] = "0123456789"[u % 10];
    io.end += d;
}
void write_float(stream io, double f) {
    if (f < 0) f = -f, put(io, '-');
    i64 ipart = i64(f + 0.00000001);
    write_uint(io, ipart);
    put(io, '.');
    double frac = f - ipart;
    if (frac < 0) frac = -frac;
    i64 ndigits = 0, nzeroes = -1;
    while (frac - i64(frac) >= 0.0000001 && frac - i64(frac) <= 0.9999999 && ndigits < FP_PRECISION) {
        if (i64(frac) == 0) nzeroes ++;
        ndigits ++, frac *= 10;
    }
    if (frac - i64(frac) > 0.9999999) frac ++;
    for (i64 i = 0; i < nzeroes; i ++) put(io, '0');
    write_uint(io, i64(frac));
}

struct OutStream {
	void* data;
	void function(ubyte) put;
}

void testStackTrace() {
	initDbgHelp;

	simpleStackTrace();
	richStackTrace();
	richestStackTrace();
	stdout.flush;
	//throw new Exception(null);
}

version(Windows) extern(Windows)
{
	alias HANDLE = void*;

	pragma(lib, "kernel32.lib");
	HANDLE GetCurrentProcess();
	void GetCurrentThreadStackLimits(void** stackLow, void** stackHigh);

	pragma(lib, "ntdll.lib");
	u16 RtlWalkFrameChain(void** BackTrace, u32 FramesToCapture, u32 flags);

	pragma(lib, "dbghelp.lib");
	enum u32 SYMOPT_UNDNAME = 0x00000002;
	enum u32 SYMOPT_DEFERRED_LOADS = 0x00000004;
	enum u32 SYMOPT_LOAD_LINES = 0x00000010;

	bool SymInitialize(HANDLE hProcess, const(char)* UserSearchPath, bool fInvadeProcess);
	u32 SymSetOptions(u32 SymOptions);
	u32 SymGetOptions();
	bool SymFromAddr(HANDLE hProcess, u64 Address, u64* Displacement, SYMBOL_INFO* Symbol);
	bool SymGetLineFromAddr64(HANDLE hProcess, u64 dwAddr, u32* pdwDisplacement, IMAGEHLP_LINEA64* line);
	u32 SymAddrIncludeInlineTrace(HANDLE  hProcess, u64 Address);
	bool SymQueryInlineTrace(HANDLE hProcess, u64 StartAddress, u32 StartContext, u64 StartRetAddress, u64 CurAddress, u32* CurContext, u32* CurFrameIndex);
	bool SymFromInlineContext(HANDLE hProcess, u64 Address, u32 InlineContext, u64* Displacement, SYMBOL_INFO* Symbol);
	bool SymGetLineFromInlineContext(HANDLE hProcess, u64 qwAddr, u32 InlineContext, u64 qwModuleBaseAddress, u32* pdwDisplacement, IMAGEHLP_LINEA64* Line64);

	struct SYMBOL_INFO {
		u32 SizeOfStruct = SYMBOL_INFO.sizeof;
		u32 TypeIndex;
		u64[2] Reserved;
		u32 Index;
		u32 Size;
		u64 ModBase;
		u32 Flags;
		u64 Value;
		u64 Address;
		u32 Register;
		u32 Scope;
		u32 Tag;
		u32 NameLen;
		u32 MaxNameLen;
		char[1] Name;
	}

	struct IMAGEHLP_LINEA64 {
		u32 SizeOfStruct = IMAGEHLP_LINEA64.sizeof;
		void* Key;
		u32 LineNumber;
		const(char)* FileName;
		u64 Address;
	}
}

void simpleStackTrace() {
	// On XP the limit is 63 frames
	u32 numFramesToCapture = 63;
	void*[63] trace;
	u16 numFramesCaptured = RtlWalkFrameChain(trace.ptr, numFramesToCapture, 0);

	writefln("numFramesCaptured %s", numFramesCaptured);
	foreach(frame; trace[0..numFramesCaptured]) {
		writefln("0x%X", frame);
	}
}

void stackLimits() {
	void* stackLow;
	void* stackHigh;
	GetCurrentThreadStackLimits(&stackLow, &stackHigh);
	writefln("stack low: 0x%X high: 0x%X", stackLow, stackHigh);
}

void initDbgHelp()
{
	SymSetOptions(SymGetOptions() | SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES);

	HANDLE hProcess = GetCurrentProcess();
	SymInitialize(hProcess, null, true);
}

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
