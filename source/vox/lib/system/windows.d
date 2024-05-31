/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.system.windows;

version(Windows) version(X86_64) @nogc nothrow @system:

import vox.lib.types;

void writeString(const(char)[] str) {
	HANDLE handle = GetStdHandle(STD_OUTPUT_HANDLE);
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
bool CloseHandle(HANDLE hObject);
noreturn ExitProcess(u32 uExitCode);
HANDLE CreateThread(void* lpThreadAttributes, usz dwStackSize, void* lpStartAddress, void* lpParameter, u32 dwCreationFlags, u32* lpThreadId);
u32 GetThreadId(HANDLE Thread);
enum u32 INFINITE = 0xFFFFFFFF;
u32 WaitForSingleObject(HANDLE hHandle, u32 dwMilliseconds);
HANDLE GetCurrentProcess();
HANDLE GetStdHandle(u32 nStdHandle);
void GetCurrentThreadStackLimits(void** stackLow, void** stackHigh);
HANDLE CreateFileA(
	const(char)*         lpFileName,
	u32                  dwDesiredAccess,
	u32                  dwShareMode,
	SECURITY_ATTRIBUTES* lpSecurityAttributes,
	u32                  dwCreationDisposition,
	u32                  dwFlagsAndAttributes,
	HANDLE               hTemplateFile
);
bool WriteFile(
	HANDLE hFile,
	u8*          lpBuffer,
	u32          nNumberOfBytesToWrite,
	u32*         lpNumberOfBytesWritten,
	OVERLAPPED*  lpOverlapped
);
bool ReadFile(
	HANDLE      hFile,
	u8*         lpBuffer,
	u32         nNumberOfBytesToRead,
	u32*        lpNumberOfBytesRead,
	OVERLAPPED* lpOverlapped
);
enum HANDLE INVALID_HANDLE_VALUE = cast(HANDLE)-1;
enum u32 STD_INPUT_HANDLE  = 0xFFFFFFF6;
enum u32 STD_OUTPUT_HANDLE = 0xFFFFFFF5;
enum u32 STD_ERROR_HANDLE  = 0xFFFFFFF4;
// dwCreationDisposition
enum u32 CREATE_NEW            = 0x00000001;
enum u32 CREATE_ALWAYS         = 0x00000002;
enum u32 OPEN_EXISTING         = 0x00000003;
enum u32 OPEN_ALWAYS           = 0x00000004;
enum u32 TRUNCATE_EXISTING     = 0x00000005;
// dwFlagsAndAttributes
enum u32 FILE_ATTRIBUTE_READONLY  = 0x00000001;
enum u32 FILE_ATTRIBUTE_HIDDEN    = 0x00000002;
enum u32 FILE_ATTRIBUTE_SYSTEM    = 0x00000004;
enum u32 FILE_ATTRIBUTE_ARCHIVE   = 0x00000020;
enum u32 FILE_ATTRIBUTE_NORMAL    = 0x00000080;
enum u32 FILE_ATTRIBUTE_TEMPORARY = 0x00000100;
enum u32 FILE_ATTRIBUTE_OFFLINE   = 0x00001000;
enum u32 FILE_ATTRIBUTE_ENCRYPTED = 0x00004000;

enum u32 GENERIC_WRITE         = 0x40000000;
void* VirtualAlloc(void* lpAddress, usz dwSize, u32 flAllocationType, u32 flProtect);
bool VirtualFree(void* lpAddress, usz dwSize, u32 dwFreeType);
bool VirtualProtect(void* lpAddress, usz dwSize, u32 flNewProtect, u32* lpflOldProtect);
bool FlushInstructionCache(void* hProcess, void* lpBaseAddress, usz dwSize);
u32 GetLastError();

bool QueryPerformanceCounter(i64* lpPerformanceCount);
void QueryPerformanceFrequency(i64* frequency);

u32 GetCurrentThreadId();

enum : u32 {
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

enum : u32 {
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

struct SECURITY_ATTRIBUTES {
	u32 nLength;
	void* lpSecurityDescriptor;
	bool bInheritHandle;
}

struct OVERLAPPED {
	u64* Internal;
	u64* InternalHigh;
	union {
		struct {
			u32 Offset;
			u32 OffsetHigh;
		}
		void* Pointer;
	}
	HANDLE hEvent;
}


pragma(lib, "ntdll.lib");
alias NTSTATUS = i32;
enum NTSTATUS STATUS_SUCCESS = 0x00000000;
enum NTSTATUS STATUS_INVALID_PARAMETER = 0xC000000D;
enum NTSTATUS STATUS_TIMEOUT = 0x00000102;

u16 RtlWalkFrameChain(void** BackTrace, u32 FramesToCapture, u32 flags);
// Windows 8+
// [in, opt] Timeout
//           Multiple of 100ns
//           Positive values are absolute date and time
//           Negative values are relative to now
//           0 - immediate return
//           null - infinite wait
//           See also: https://learn.microsoft.com/en-us/windows/win32/api/minwinbase/ns-minwinbase-filetime
NTSTATUS RtlWaitOnAddress(
	void* Address,
	void* CompareAddress,
	usz AddressSize,
	i64* Timeout
);
void RtlWakeAddressAll(void* addr);
void RtlWakeAddressSingle(void* addr);


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
