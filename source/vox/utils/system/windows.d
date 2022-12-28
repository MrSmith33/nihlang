/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.utils.system.windows;

version(Windows) version(X86_64) @nogc nothrow @system:

import vox.utils.types;

void writeString(const(char)[] str) {
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


extern(Windows):


alias HANDLE = void*;

pragma(lib, "kernel32.lib");
noreturn ExitProcess(uint uExitCode);
HANDLE GetCurrentProcess();
HANDLE GetStdHandle(u32 nStdHandle);
void GetCurrentThreadStackLimits(void** stackLow, void** stackHigh);
bool WriteFile(
	void* hFile,
	u8* lpBuffer,
	u32 nNumberOfCharsToWrite,
	u32* lpNumberOfCharsWritten,
	void* lpOverlapped
);
enum u32 STD_INPUT_HANDLE  = 0xFFFFFFF6;
enum u32 STD_OUTPUT_HANDLE = 0xFFFFFFF5;
enum u32 STD_ERROR_HANDLE  = 0xFFFFFFF4;


pragma(lib, "ntdll.lib");
u16 RtlWalkFrameChain(void** BackTrace, u32 FramesToCapture, u32 flags);


pragma(lib, "dbghelp.lib");
bool SymInitialize(HANDLE hProcess, const(char)* UserSearchPath, bool fInvadeProcess);
u32 SymSetOptions(u32 SymOptions);
u32 SymGetOptions();
bool SymFromAddr(HANDLE hProcess, u64 Address, u64* Displacement, SYMBOL_INFO* Symbol);
bool SymGetLineFromAddr64(HANDLE hProcess, u64 dwAddr, u32* pdwDisplacement, IMAGEHLP_LINEA64* line);
u32 SymAddrIncludeInlineTrace(HANDLE  hProcess, u64 Address);
bool SymQueryInlineTrace(HANDLE hProcess, u64 StartAddress, u32 StartContext, u64 StartRetAddress, u64 CurAddress, u32* CurContext, u32* CurFrameIndex);
bool SymFromInlineContext(HANDLE hProcess, u64 Address, u32 InlineContext, u64* Displacement, SYMBOL_INFO* Symbol);
bool SymGetLineFromInlineContext(HANDLE hProcess, u64 qwAddr, u32 InlineContext, u64 qwModuleBaseAddress, u32* pdwDisplacement, IMAGEHLP_LINEA64* Line64);

enum u32 SYMOPT_UNDNAME = 0x00000002;
enum u32 SYMOPT_DEFERRED_LOADS = 0x00000004;
enum u32 SYMOPT_LOAD_LINES = 0x00000010;

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
