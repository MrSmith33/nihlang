/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.system.windows;

version(Windows) version(X86_64) @nogc nothrow @system:

import vox.lib.types;

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

void* VirtualAlloc(void* lpAddress, size_t dwSize, uint flAllocationType, uint flProtect);
bool VirtualFree(void* lpAddress, size_t dwSize, uint dwFreeType);
bool VirtualProtect(void* lpAddress, size_t dwSize, uint flNewProtect, uint* lpflOldProtect);
bool FlushInstructionCache(void* hProcess, void* lpBaseAddress, size_t dwSize);
uint GetLastError() @trusted;

bool QueryPerformanceCounter(long* lpPerformanceCount);
void QueryPerformanceFrequency(long* frequency);

enum : uint {
	PAGE_NOACCESS          = 0x0001,
	PAGE_READONLY          = 0x0002,
	PAGE_READWRITE         = 0x0004,
	PAGE_WRITECOPY         = 0x0008,
	PAGE_EXECUTE           = 0x0010,
	PAGE_EXECUTE_READ      = 0x0020,
	PAGE_EXECUTE_READWRITE = 0x0040,
	PAGE_EXECUTE_WRITECOPY = 0x0080,
	PAGE_GUARD             = 0x0100,
	PAGE_NOCACHE           = 0x0200,
}

enum : uint {
	MEM_COMMIT      = 0x00001000,
	MEM_RESERVE     = 0x00002000,
	MEM_DECOMMIT    = 0x00004000,
	MEM_RELEASE     = 0x00008000,
	MEM_FREE        = 0x00010000,
	MEM_PRIVATE     = 0x00020000,
	MEM_MAPPED      = 0x00040000,
	MEM_RESET       = 0x00080000,
	MEM_TOP_DOWN    = 0x00100000,
	MEM_WRITE_WATCH = 0x00200000,
	MEM_PHYSICAL    = 0x00400000,
	MEM_4MB_PAGES   = 0x80000000,
}


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
