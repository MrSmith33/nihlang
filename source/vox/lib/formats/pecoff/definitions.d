/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.formats.pecoff.definitions;

import vox.lib;

@nogc nothrow:

struct DosHeader {
	@nogc nothrow:
	// Magic number
	char[2] magic = ['M', 'Z'];
	// Bytes on last page of file
	u16 lastsize = 0x90;
	// Pages in file
	u16 nblocks = 0x03;
	// Relocations
	u16 nreloc = 0;
	// Size of header in paragraphs
	u16 hdrsize = 0x04;
	// Minimum extra paragraphs needed
	u16 minalloc = 0;
	// Maximum extra paragraphs needed
	u16 maxalloc = u16.max;
	// Initial (relative) SS value
	u16 ss = 0;
	// Initial SP value
	u16 sp = 0xB8;
	// Checksum
	u16 checksum = 0;
	// Initial IP value
	u16 ip = 0;
	// Initial (relative) CS value
	u16 cs = 0;
	// File address of relocation table
	u16 relocpos;
	// Overlay number
	u16 noverlay;
	// Reserved words
	u16[4] reserved1;
	// OEM identifier (for e_oeminfo)
	u16 oem_id;
	// OEM information; e_oemid specific
	u16 oem_info;
	// Reserved words
	u16[10] reserved2;
	// File address of new exe header
	// Offset to the 'PE\0\0' signature relative to the beginning of the file
	u32 e_lfanew = DosHeader.sizeof + dosStubBytes.length;

	u32 write(ref VoxAllocator allocator, ref Array!u8 sink) {
		auto offset = sink.length;
		sink.putAsBytes(allocator, this);
		return offset;
	}

	void toString(scope SinkDelegate sink, FormatSpec spec) const {
		formattedWrite(sink, "  Magic: %s\n", magic.EscapedString);
		formattedWrite(sink, "  Bytes on last page of file: %s\n", lastsize);
		formattedWrite(sink, "  Pages in file: %s\n", nblocks);
		formattedWrite(sink, "  Relocations: %s\n", nreloc);
		formattedWrite(sink, "  Size of header in paragraphs: %s\n", hdrsize);
		formattedWrite(sink, "  Minimum extra paragraphs needed: %s\n", minalloc);
		formattedWrite(sink, "  Maximum extra paragraphs needed: %s\n", maxalloc);
		formattedWrite(sink, "  Initial (relative) SS value: %s\n", ss);
		formattedWrite(sink, "  Initial SP value: %s\n", sp);
		formattedWrite(sink, "  Checksum: %s\n", checksum);
		formattedWrite(sink, "  Initial IP value: %s\n", ip);
		formattedWrite(sink, "  Initial (relative) CS value: %s\n", cs);
		formattedWrite(sink, "  File address of relocation table: %s\n", relocpos);
		formattedWrite(sink, "  Overlay number: %s\n", noverlay);
		formattedWrite(sink, "  Reserved words: %s\n", reserved1);
		formattedWrite(sink, "  OEM identifier: %s\n", oem_id);
		formattedWrite(sink, "  OEM information: %s\n", oem_info);
		formattedWrite(sink, "  Reserved words: %s\n", reserved2);
		formattedWrite(sink, "  File address of new exe header: %s\n", e_lfanew);
	}

	usz fileSize() const => DosHeader.sizeof;
}
static assert(DosHeader.sizeof == 64);

/// MS-DOS Stub (Image Only)
///
/// The MS-DOS stub is a valid application that runs under MS-DOS. It is placed at the
/// front of the EXE image. The linker places a default stub here, which prints out the
/// message “This program cannot be run in DOS mode” when the image is run in
/// MS-DOS. The user can specify a different stub by using the /STUB linker option.
/// At location 0x3c, the stub has the file offset to the PE signature. This information
/// enables Windows to properly execute the image file, even though it has an
/// MS-DOS stub. This file offset is placed at location 0x3c during linking.
struct DosStub {
	@nogc nothrow:
	const(u8)[] data = dosStubBytes[];

	u32 write(ref VoxAllocator allocator, ref Array!u8 sink) {
		auto offset = sink.length;
		sink.put(allocator, data);
		return offset;
	}

	void toString(scope SinkDelegate sink, FormatSpec spec) const {
		foreach(b; data)
			formattedWrite(sink, "%02X", b);
		formattedWrite(sink, "\n");
	}

	usz fileSize() const => data.length;
}

immutable u8[136] dosStubBytes = cast(u8[])x"
	0E1FBA0E00B409CD21B8014CCD21546869732070726F6772616D2063616E6E6F7420
	62652072756E20696E20444F53206D6F64652E0D0D0A2400000000000000A9187F5E
	ED79110DED79110DED79110DA601100CEA79110DED79100DF179110DED79110DEC79
	110DFEFD110CEC79110DFEFD130CEC79110D52696368ED79110D0000000000000000";

struct PeSignature {
	@nogc nothrow:
	char[4] signature = "PE\0\0";

	u32 write(ref VoxAllocator allocator, ref Array!u8 sink) {
		auto offset = sink.length;
		sink.putAsBytes(allocator, this);
		return offset;
	}

	void toString(scope SinkDelegate sink, FormatSpec spec) const {
		formattedWrite(sink, "  %s\n", signature.EscapedString);
	}

	usz fileSize() const => PeSignature.sizeof;
}
static assert(PeSignature.sizeof == 4);

/// The Machine field has one of the following values that specifies its CPU type. An
/// image file can be run only on the specified machine or on a system that emulates
/// the specified machine.
enum MachineType : u16 {
	amd64 = 0x8664, /// x64
	i386 = 0x14C,   /// Intel 386 or later processors and compatible processors
	arm = 0x1C0,    /// ARM little endian
	arm64 = 0xAA64, /// ARM64 little endian
}

struct MachineTypePrinter {
	@nogc nothrow:
	MachineType type;
	void toString(scope SinkDelegate sink, FormatSpec spec) const @nogc nothrow {
		switch (type) with(MachineType) {
			case 0: return sink("unknown");
			case amd64: return sink("amd64");
			case i386: return sink("i386");
			case arm: return sink("arm");
			case arm64: return sink("arm64");
			default: return formatValue(sink, type);
		}
	}
}

/// The Characteristics field contains flags that indicate attributes of the object or image
/// file. The following flags are currently defined:
enum CoffFlags : u16
{
	/// Image only, Windows CE, and Microsoft Windows NT® and later.
	/// This indicates that the file does not contain base relocations and must
	/// therefore be loaded at its preferred base address. If the base address is
	/// not available, the loader reports an error. The default behavior of the
	/// linker is to strip base relocations from executable (EXE) files.
	RELOCS_STRIPPED = 0x0001,

	/// Image only. This indicates that the image file is valid and can be run. If
	/// this flag is not set, it indicates a linker error.
	EXECUTABLE_IMAGE = 0x0002,

	//  COFF line numbers have been removed. This flag is deprecated and should be zero.
	LINE_NUMS_STRIPPED = 0x0004,

	//  COFF symbol table entries for local symbols have been removed. This
	//  flag is deprecated and should be zero.
	LOCAL_SYMS_STRIPPED = 0x0008,

	//  Obsolete. Aggressively trim working set. This flag is deprecated for
	//  Windows 2000 and later and must be zero.
	AGGRESSIVE_WS_TRIM = 0x0010,

	/// Application can handle > 2-GB addresses.
	LARGE_ADDRESS_AWARE = 0x0020,

	//  Little endian: the least significant bit (LSB) precedes the most significant
	//  bit (MSB) in memory. This flag is deprecated and should be zero.
	BYTES_REVERSED_LO = 0x0080,

	/// Machine is based on a 32-bit-word architecture.
	_32BIT_MACHINE = 0x0100,

	/// Debugging information is removed from the image file.
	DEBUG_STRIPPED = 0x0200,

	/// If the image is on removable media, fully load it and copy it to the swap file.
	REMOVABLE_RUN_FROM_SWAP = 0x0400,

	/// If the image is on network media, fully load it and copy it to the swap file.
	NET_RUN_FROM_SWAP = 0x0800,

	/// The image file is a system file, not a user program.
	SYSTEM = 0x1000,

	/// The image file is a dynamic-link library (DLL). Such files are
	/// considered executable files for almost all purposes, although they cannot be directly run.
	DLL = 0x2000,

	/// The file should be run only on a uniprocessor machine.
	UP_SYSTEM_ONLY = 0x4000,

	//  Big endian: the MSB precedes the LSB in memory. This flag is deprecated and should be zero
	BYTES_REVERSED_HI = 0x8000,
}

/// COFF File Header (Object and Image)
///
/// At the beginning of an object file, or immediately after the signature of an image file,
/// is a standard COFF file header in the following format. Note that the Windows
/// loader limits the number of sections to 96.
struct CoffFileHeader {
	@nogc nothrow:
	/// The number that identifies the type of target machine.
	MachineType Machine;

	/// The number of sections. This indicates the size of
	/// the section table, which immediately follows the headers.
	u16 NumberOfSections;

	/// The low 32 bits of the number of seconds since
	/// 00:00 January 1, 1970 (a C run-time time_t
	/// value), that indicates when the file was created.
	u32 TimeDateStamp;

	/// The file offset of the COFF symbol table, or zero
	/// if no COFF symbol table is present. This value
	/// should be zero for an image because COFF
	/// debugging information is deprecated.
	u32 PointerToSymbolTable;

	/// The number of entries in the symbol table. This
	/// data can be used to locate the string table, which
	/// immediately follows the symbol table. This value
	/// should be zero for an image because COFF
	/// debugging information is deprecated.
	u32 NumberOfSymbols;

	/// The size of the optional header, which is required
	/// for executable files but not for object files. This
	/// value should be zero for an object file. For a
	/// description of the header format, see section 3.4,
	/// “Optional Header (Image Only).
	u16 SizeOfOptionalHeader = 240;

	/// The flags that indicate the attributes of the file.
	/// See CoffFlags.
	u16 Characteristics;

	u32 write(ref VoxAllocator allocator, ref Array!u8 sink) {
		auto offset = sink.length;
		sink.putAsBytes(allocator, this);
		return offset;
	}

	void toString(scope SinkDelegate sink, FormatSpec spec) const {
		formattedWrite(sink, "  Machine type: %s\n", Machine.MachineTypePrinter);
		formattedWrite(sink, "  Number of sections: %s\n", NumberOfSections);
		formattedWrite(sink, "  TimeDateStamp: %s\n", TimeDateStamp);
		formattedWrite(sink, "  Pointer to symbol table: 0x%08X\n", PointerToSymbolTable);
		formattedWrite(sink, "  Number of symbols: %s\n", NumberOfSymbols);
		formattedWrite(sink, "  Size of optional header: %s\n", SizeOfOptionalHeader);
		formattedWrite(sink, "  Characteristics: 0x%04X\n", Characteristics);
		if(Characteristics) with(CoffFlags)
		{
			auto c = Characteristics;
			if(c & RELOCS_STRIPPED) formattedWrite(sink, "    Relocations stripped\n");
			if(c & EXECUTABLE_IMAGE) formattedWrite(sink, "    Executable image\n");
			if(c & LINE_NUMS_STRIPPED) formattedWrite(sink, "    Line numbers stripped\n");
			if(c & LOCAL_SYMS_STRIPPED) formattedWrite(sink, "    Local symbols stripped\n");
			if(c & AGGRESSIVE_WS_TRIM) formattedWrite(sink, "    Aggressively trim working set\n");
			if(c & LARGE_ADDRESS_AWARE) formattedWrite(sink, "    Large address aware\n");
			if(c & BYTES_REVERSED_LO) formattedWrite(sink, "    Bytes reversed low\n");
			if(c & _32BIT_MACHINE) formattedWrite(sink, "    32bit machine\n");
			if(c & DEBUG_STRIPPED) formattedWrite(sink, "    Debug stripped\n");
			if(c & REMOVABLE_RUN_FROM_SWAP) formattedWrite(sink, "    Removable run from swap\n");
			if(c & NET_RUN_FROM_SWAP) formattedWrite(sink, "    Network run from swap\n");
			if(c & SYSTEM) formattedWrite(sink, "    System\n");
			if(c & DLL) formattedWrite(sink, "    DLL\n");
			if(c & UP_SYSTEM_ONLY) formattedWrite(sink, "    Up system only\n");
			if(c & BYTES_REVERSED_HI) formattedWrite(sink, "    Bytes reversed high\n");
		}
	}

	usz fileSize() const => CoffFileHeader.sizeof;
}
static assert(CoffFileHeader.sizeof == 20);

struct ImageDataDirectory {
	u32 VirtualAddress;
	u32 Size;
}

enum DEFAULT_SECTION_ALIGNMENT = 4096;
enum DEFAULT_FILE_ALIGNMENT = 512;

/// Optional Header (Image Only)
///
/// Every image file has an optional header that provides information to the loader. This
/// header is optional in the sense that some files (specifically, object files) do not have
/// it. For image files, this header is required. An object file can have an optional
/// header, but generally this header has no function in an object file except to increase
/// its size.
/// Note that the size of the optional header is not fixed. The SizeOfOptionalHeader
/// field in the COFF header must be used to validate that a probe into the file for a
/// particular data directory does not go beyond SizeOfOptionalHeader. For more
/// information, see section 3.3, “COFF File Header (Object and Image).”
/// The NumberOfRvaAndSizes field of the optional header should also be used to
/// ensure that no probe for a particular data directory entry goes beyond the optional
/// header. In addition, it is important to validate the optional header magic number for
/// format compatibility.
/// The optional header magic number determines whether an image is a PE32 or PE32+ executable.
/// | Magic number + PE format
/// | 0x10b        | PE32
/// | 0x20b        | PE32+
/// PE32+ images allow for a 64-bit address space while limiting the image size to
/// 2 gigabytes. Other PE32+ modifications are addressed in their respective sections.
/// The optional header itself has three major parts
///
/// struct defines PE32+
struct OptionalHeader {
	@nogc nothrow:

	/// The unsigned integer that identifies the
	/// state of the image file. The most common
	/// number is 0x10B, which identifies it as a
	/// normal executable file. 0x107 identifies it as
	/// a ROM image, and 0x20B identifies it as a
	/// PE32+ executable.
	u16 Magic = 0x20B;

	/// The linker major version number.
	u8 MajorLinkerVersion;

	/// The linker minor version number.
	u8 MinorLinkerVersion;

	/// The size of the code (text) section, or the
	/// sum of all code sections if there are multiple
	/// sections.
	u32 SizeOfCode;

	/// The size of the initialized data section, or
	/// the sum of all such sections if there are
	/// multiple data sections.
	u32 SizeOfInitializedData;

	/// The size of the uninitialized data section
	/// (BSS), or the sum of all such sections if
	/// there are multiple BSS sections.
	u32 SizeOfUninitializedData;

	/// The address of the entry point relative to the
	/// image base when the executable file is
	/// loaded into memory. For program images,
	/// this is the starting address. For device
	/// drivers, this is the address of the
	/// initialization function. An entry point is
	/// optional for DLLs. When no entry point is
	/// present, this field must be zero.
	u32 AddressOfEntryPoint;

	/// The address that is relative to the image
	/// base of the beginning-of-code section when
	/// it is loaded into memory.
	u32 BaseOfCode;

	/// The preferred address of the first
	/// byte of image when loaded into
	/// memory; must be a multiple of 64 K.
	/// The default for DLLs is 0x10000000.
	/// The default for Windows CE EXEs is
	/// 0x00010000. The default for
	/// Windows NT, Windows 2000,
	/// Windows XP, Windows 95,
	/// Windows 98, and Windows Me is
	/// 0x00400000.
	u64 ImageBase = 0x00400000;

	/// The alignment (in bytes) of sections
	/// when they are loaded into memory. It
	/// must be greater than or equal to
	/// FileAlignment. The default is the
	/// page size for the architecture.
	u32 SectionAlignment = DEFAULT_SECTION_ALIGNMENT;

	/// The alignment factor (in bytes) that is
	/// used to align the raw data of sections
	/// in the image file. The value should be
	/// a power of 2 between 512 and 64 K,
	/// inclusive. The default is 512. If the
	/// SectionAlignment is less than the
	/// architecture’s page size, then
	/// FileAlignment must match
	/// SectionAlignment.
	u32 FileAlignment = DEFAULT_FILE_ALIGNMENT;

	/// The major version number of the
	/// required operating system.
	u16 MajorOperatingSystemVersion;

	/// The minor version number of the
	/// required operating system.
	u16 MinorOperatingSystemVersion;

	/// The major version number of the
	/// image.
	u16 MajorImageVersion;

	/// The minor version number of the
	/// image.
	u16 MinorImageVersion;

	/// The major version number of the
	/// subsystem.
	u16 MajorSubsystemVersion;

	/// The minor version number of the
	/// subsystem.
	u16 MinorSubsystemVersion;

	/// Reserved, must be zero.
	u32 Win32VersionValue = 0;

	/// The size (in bytes) of the image,
	/// including all headers, as the image is
	/// loaded in memory. It must be a
	/// multiple of SectionAlignment.
	u32 SizeOfImage;

	/// The combined size of an MS-DOS
	/// stub, PE header, and section
	/// headers rounded up to a multiple of
	/// FileAlignment.
	u32 SizeOfHeaders;

	/// The image file checksum. The
	/// algorithm for computing the
	/// checksum is incorporated into
	/// IMAGHELP.DLL. The following are
	/// checked for validation at load time:
	/// all drivers, any DLL loaded at boot
	/// time, and any DLL that is loaded into
	/// a critical Windows process.
	u32 CheckSum;

	/// The subsystem that is required to run
	/// this image. For more information, see
	/// “Windows Subsystem” later in this
	/// specification.
	u16 Subsystem;

	/// For more information, see “DLL
	/// Characteristics” later in this
	/// specification.
	u16 DllCharacteristics;

	/// The size of the stack to reserve. Only
	/// SizeOfStackCommit is committed;
	/// the rest is made available one page
	/// at a time until the reserve size is
	/// reached.
	u64 SizeOfStackReserve;

	/// The size of the stack to commit.
	u64 SizeOfStackCommit;

	/// The size of the local heap space to
	/// reserve. Only SizeOfHeapCommit is
	/// committed; the rest is made available
	/// one page at a time until the reserve
	/// size is reached.
	u64 SizeOfHeapReserve;

	/// The size of the local heap space to
	/// commit.
	u64 SizeOfHeapCommit;

	/// Reserved, must be zero.
	u32 LoaderFlags = 0;

	/// The number of data-directory entries
	/// in the remainder of the optional
	/// header. Each describes a location
	/// and size.
	u32 NumberOfRvaAndSizes = 16;

	/// The export table address and size. For more
	/// information see section 6.3, “The .edata Section
	/// (Image Only).”
	ImageDataDirectory ExportTable;

	/// The import table address and size. For more
	/// information, see section 6.4, “The .idata
	/// Section.”
	ImageDataDirectory ImportTable;

	/// The resource table address and size. For more
	/// information, see section 6.9, “The .rsrc Section.”
	ImageDataDirectory ResourceTable;

	/// The exception table address and size. For more
	/// information, see section 6.5, “The .pdata
	/// Section.”
	ImageDataDirectory ExceptionTable;

	/// The attribute certificate table address and size.
	/// For more information, see section 5.7, “The
	/// Attribute Certificate Table (Image Only).”
	ImageDataDirectory CertificateTable;

	/// The base relocation table address and size. For
	/// more information, see section 6.6, "The .reloc
	/// Section (Image Only)."
	ImageDataDirectory BaseRelocationTable;

	/// The debug data starting address and size. For
	/// more information, see section 6.1, “The .debug
	/// Section.”
	ImageDataDirectory Debug;

	/// Reserved, must be 0
	ImageDataDirectory Architecture;

	/// The RVA of the value to be stored in the global
	/// pointer register. The size member of this
	/// structure must be set to zero.
	ImageDataDirectory GlobalPtr;

	/// The thread local storage (TLS) table address
	/// and size. For more information, see section 6.7,
	/// “The .tls Section.”
	ImageDataDirectory TLSTable;

	/// The load configuration table address and size.
	/// For more information, see section 6.8, “The Load
	/// Configuration Structure (Image Only).”
	ImageDataDirectory LoadConfigTable;

	/// The bound import table address and size.
	ImageDataDirectory BoundImport;

	/// The import address table address and size. For
	/// more information, see section 6.4.4, “Import
	/// Address Table.”
	ImageDataDirectory IAT;

	/// The delay import descriptor address and size.
	/// For more information, see section 5.8, “DelayLoad Import Tables (Image Only).”
	ImageDataDirectory DelayImportDescriptor;

	/// The CLR runtime header address and size. For
	/// more information, see section 6.10, “The
	/// .cormeta Section (Object Only).”
	ImageDataDirectory CLRRuntimeHeader;

	u64 _reserved; /// Reserved, must be zero

	u32 write(ref VoxAllocator allocator, ref Array!u8 sink) {
		auto offset = sink.length;
		sink.putAsBytes(allocator, this);
		return offset;
	}

	void toString(scope SinkDelegate sink, FormatSpec spec) const {
		formattedWrite(sink, "  Magic: 0x%X\n", Magic);
		formattedWrite(sink, "  Linker major version: %s\n", MajorLinkerVersion);
		formattedWrite(sink, "  Linker minor version: %s\n", MinorLinkerVersion);
		formattedWrite(sink, "  SizeOfCode: %s\n", SizeOfCode);
		formattedWrite(sink, "  SizeOfInitializedData: %s\n", SizeOfInitializedData);
		formattedWrite(sink, "  SizeOfUninitializedData: %s\n", SizeOfUninitializedData);
		formattedWrite(sink, "  AddressOfEntryPoint: 0x%X\n", AddressOfEntryPoint);
		formattedWrite(sink, "  BaseOfCode: 0x%X\n", BaseOfCode);
		formattedWrite(sink, "  ImageBase: 0x%X\n", ImageBase);
		formattedWrite(sink, "  SectionAlignment: %s\n", SectionAlignment);
		formattedWrite(sink, "  FileAlignment: %s\n", FileAlignment);
		formattedWrite(sink, "  MajorOperatingSystemVersion: %s\n", MajorOperatingSystemVersion);
		formattedWrite(sink, "  MinorOperatingSystemVersion: %s\n", MinorOperatingSystemVersion);
		formattedWrite(sink, "  MajorImageVersion: %s\n", MajorImageVersion);
		formattedWrite(sink, "  MinorImageVersion: %s\n", MinorImageVersion);
		formattedWrite(sink, "  MajorSubsystemVersion: %s\n", MajorSubsystemVersion);
		formattedWrite(sink, "  MinorSubsystemVersion: %s\n", MinorSubsystemVersion);
		formattedWrite(sink, "  Win32VersionValue: %s\n", Win32VersionValue);
		formattedWrite(sink, "  SizeOfImage: %s\n", SizeOfImage);
		formattedWrite(sink, "  SizeOfHeaders: %s\n", SizeOfHeaders);
		formattedWrite(sink, "  CheckSum: %s\n", CheckSum);
		formattedWrite(sink, "  Subsystem: %s\n", Subsystem);
		formattedWrite(sink, "  DllCharacteristics: 0x%X\n", DllCharacteristics);
		formattedWrite(sink, "  SizeOfStackReserve: 0x%X\n", SizeOfStackReserve);
		formattedWrite(sink, "  SizeOfStackCommit: 0x%X\n", SizeOfStackCommit);
		formattedWrite(sink, "  SizeOfHeapReserve: 0x%X\n", SizeOfHeapReserve);
		formattedWrite(sink, "  SizeOfHeapCommit: 0x%X\n", SizeOfHeapCommit);
		formattedWrite(sink, "  LoaderFlags: %s\n", LoaderFlags);
		formattedWrite(sink, "  NumberOfRvaAndSizes: %s\n", NumberOfRvaAndSizes);
		formattedWrite(sink, "  ExportTable\n    VirtualAddress: %s\n    Size: %s\n", ExportTable.VirtualAddress, ExportTable.Size);
		formattedWrite(sink, "  ImportTable\n    VirtualAddress: %s\n    Size: %s\n", ImportTable.VirtualAddress, ImportTable.Size);
		formattedWrite(sink, "  ResourceTable\n    VirtualAddress: %s\n    Size: %s\n", ResourceTable.VirtualAddress, ResourceTable.Size);
		formattedWrite(sink, "  ExceptionTable\n    VirtualAddress: %s\n    Size: %s\n", ExceptionTable.VirtualAddress, ExceptionTable.Size);
		formattedWrite(sink, "  CertificateTable\n    VirtualAddress: %s\n    Size: %s\n", CertificateTable.VirtualAddress, CertificateTable.Size);
		formattedWrite(sink, "  BaseRelocationTable\n    VirtualAddress: %s\n    Size: %s\n", BaseRelocationTable.VirtualAddress, BaseRelocationTable.Size);
		formattedWrite(sink, "  Debug\n    VirtualAddress: %s\n    Size: %s\n", Debug.VirtualAddress, Debug.Size);
		formattedWrite(sink, "  Architecture\n    VirtualAddress: %s\n    Size: %s\n", Architecture.VirtualAddress, Architecture.Size);
		formattedWrite(sink, "  GlobalPtr\n    VirtualAddress: %s\n    Size: %s\n", GlobalPtr.VirtualAddress, GlobalPtr.Size);
		formattedWrite(sink, "  TLSTable\n    VirtualAddress: %s\n    Size: %s\n", TLSTable.VirtualAddress, TLSTable.Size);
		formattedWrite(sink, "  LoadConfigTable\n    VirtualAddress: %s\n    Size: %s\n", LoadConfigTable.VirtualAddress, LoadConfigTable.Size);
		formattedWrite(sink, "  BoundImport\n    VirtualAddress: %s\n    Size: %s\n", BoundImport.VirtualAddress, BoundImport.Size);
		formattedWrite(sink, "  IAT\n    VirtualAddress: %s\n    Size: %s\n", IAT.VirtualAddress, IAT.Size);
		formattedWrite(sink, "  DelayImportDescriptor\n    VirtualAddress: %s\n    Size: %s\n", DelayImportDescriptor.VirtualAddress, DelayImportDescriptor.Size);
		formattedWrite(sink, "  CLRRuntimeHeader\n    VirtualAddress: %s\n    Size: %s\n", CLRRuntimeHeader.VirtualAddress, CLRRuntimeHeader.Size);
		formattedWrite(sink, "  _reserved: %s\n", _reserved);
	}

	usz fileSize() const => OptionalHeader.sizeof;
}
static assert(OptionalHeader.sizeof == 240);

enum SectionFlags : u32 {
	/// The section contains executable code.
	SCN_CNT_CODE = 0x00000020,
	/// The section contains initialized data.
	SCN_CNT_INITIALIZED_DATA = 0x00000040,
	/// The section contains uninitialized data.
	SCN_CNT_UNINITIALIZED_DATA = 0x00000080,
	/// The section contains comments or
	/// other information. The .drectve section has this type. This is valid
	/// for object files only.
	SCN_LNK_INFO = 0x00000200,
	/// The section will not become part
	/// of the image. This is valid only for object files.
	SCN_LNK_REMOVE = 0x00000800,
	/// The section contains COMDAT data. For more information, see
	/// section 5.5.6, “COMDAT Sections (Object Only).” This is valid only for object files.
	SCN_LNK_COMDAT = 0x00001000,
	/// The section contains data referenced through the global pointer (GP).
	SCN_GPREL = 0x00008000,
	/// Align data on a    1-byte boundary. Valid only for object files.
	SCN_ALIGN_1BYTES = 0x00100000,
	/// Align data on a    2-byte boundary. Valid only for object files.
	SCN_ALIGN_2BYTES = 0x00200000,
	/// Align data on a    4-byte boundary. Valid only for object files.
	SCN_ALIGN_4BYTES = 0x00300000,
	/// Align data on a    8-byte boundary. Valid only for object files.
	SCN_ALIGN_8BYTES = 0x00400000,
	/// Align data on a   16-byte boundary. Valid only for object files.
	SCN_ALIGN_16BYTES = 0x00500000,
	/// Align data on a   32-byte boundary. Valid only for object files.
	SCN_ALIGN_32BYTES = 0x00600000,
	/// Align data on a   64-byte boundary. Valid only for object files.
	SCN_ALIGN_64BYTES = 0x00700000,
	/// Align data on a  128-byte boundary. Valid only for object files.
	SCN_ALIGN_128BYTES = 0x00800000,
	/// Align data on a  256-byte boundary. Valid only for object files.
	SCN_ALIGN_256BYTES = 0x00900000,
	/// Align data on a  512-byte boundary. Valid only for object files.
	SCN_ALIGN_512BYTES = 0x00A00000,
	/// Align data on a 1024-byte boundary. Valid only for object files.
	SCN_ALIGN_1024BYTES = 0x00B00000,
	/// Align data on a 2048-byte boundary. Valid only for object files.
	SCN_ALIGN_2048BYTES = 0x00C00000,
	/// Align data on a 4096-byte boundary. Valid only for object files.
	SCN_ALIGN_4096BYTES = 0x00D00000,
	/// Align data on a 8192-byte boundary. Valid only for object files.
	SCN_ALIGN_8192BYTES = 0x00E00000,
	/// The section contains extended relocations.
	SCN_LNK_NRELOC_OVFL = 0x01000000,
	/// The section can be discarded as needed.
	SCN_MEM_DISCARDABLE = 0x02000000,
	/// The section cannot be cached.
	SCN_MEM_NOT_CACHED = 0x04000000,
	/// The section is not pageable.
	SCN_MEM_NOT_PAGED = 0x08000000,
	/// The section can be shared in memory.
	SCN_MEM_SHARED = 0x10000000,
	/// The section can be executed as code.
	SCN_MEM_EXECUTE = 0x20000000,
	/// The section can be read.
	SCN_MEM_READ = 0x40000000,
	/// The section can be written to.
	SCN_MEM_WRITE = 0x80000000,
}

struct SectionHeader {
	@nogc nothrow:
	/// An 8-byte, null-padded UTF-8 encoded string. If
	/// the string is exactly 8 characters long, there is no
	/// terminating null. For longer names, this field
	/// contains a slash (/) that is followed by an ASCII
	/// representation of a decimal number that is an
	/// offset into the string table. Executable images do
	/// not use a string table and do not support section
	/// names longer than 8 characters. Long names in
	/// object files are truncated if they are emitted to an
	/// executable file.
	char[8] Name;

	/// The total size of the section when loaded into
	/// memory. If this value is greater than
	/// SizeOfRawData, the section is zero-padded. This
	/// field is valid only for executable images and
	/// should be set to zero for object files.
	u32 VirtualSize;

	/// For executable images, the address of the first
	/// byte of the section relative to the image base
	/// when the section is loaded into memory. For
	/// object files, this field is the address of the first
	/// byte before relocation is applied; for simplicity,
	/// compilers should set this to zero. Otherwise, it is
	/// an arbitrary value that is subtracted from offsets
	/// during relocation.
	u32 VirtualAddress;

	/// The size of the section (for object files) or the
	/// size of the initialized data on disk (for image
	/// files). For executable images, this must be a
	/// multiple of FileAlignment from the optional
	/// header. If this is less than VirtualSize, the
	/// remainder of the section is zero-filled. Because
	/// the SizeOfRawData field is rounded but the
	/// VirtualSize field is not, it is possible for
	/// SizeOfRawData to be greater than VirtualSize as
	/// well. When a section contains only uninitialized
	/// data, this field should be zero.
	u32 SizeOfRawData;

	/// The file pointer to the first page of the section
	/// within the COFF file. For executable images, this
	/// must be a multiple of FileAlignment from the
	/// optional header. For object files, the value should
	/// be aligned on a 4-byte boundary for best
	/// performance. When a section contains only
	/// uninitialized data, this field should be zero.
	u32 PointerToRawData;

	/// The file pointer to the beginning of relocation
	/// entries for the section. This is set to zero for
	/// executable images or if there are no relocations.
	u32 PointerToRelocations;

	/// The file pointer to the beginning of line-number
	/// entries for the section. This is set to zero if there
	/// are no COFF line numbers. This value should be
	/// zero for an image because COFF debugging
	/// information is deprecated.
	u32 PointerToLinenumbers = 0;

	/// The number of relocation entries for the section.
	/// This is set to zero for executable images.
	u16 NumberOfRelocations;

	/// The number of line-number entries for the
	/// section. This value should be zero for an image
	/// because COFF debugging information is
	/// deprecated.
	u16 NumberOfLinenumbers = 0;

	/// The flags that describe the characteristics of the
	/// section. See SectionFlags.
	u32 Characteristics;

	string getName(string stringTable) const {
		return nameFromSlashName(Name, stringTable);
	}

	u32 write(ref VoxAllocator allocator, ref Array!u8 sink) {
		auto offset = sink.length;
		sink.putAsBytes(allocator, this);
		return offset;
	}

	static void printTableHeader(scope SinkDelegate sink) {
		formattedWrite(sink, "Code|Initialized|Uninitialized|Link info|Remove|coMdat|Gprel|Ovfl|Discardable|cacHed|Paged|Shared\n");
		formattedWrite(sink, "----  --------  --------  --------  --------  --------  --------  -----  ------------  ---  --------\n");
		formattedWrite(sink, "      Virtual    Virtual      File      File    Relocs    Num of             Flags                  \n");
		formattedWrite(sink, "   #  Address       Size    Offset      Size    Offset    Relocs  Align  CIULRMGODHPS  RWX  Name    \n");
		formattedWrite(sink, "----  --------  --------  --------  --------  --------  --------  -----  ------------  ---  --------\n");
	}

	void print(scope SinkDelegate sink, size_t index, string stringTable) const {
		formattedWrite(sink, "% 4X  % 8X  % 8X  % 8X  % 8X  % 8X  % 8X",
			index, VirtualAddress, VirtualSize, PointerToRawData, SizeOfRawData,
			PointerToRelocations, NumberOfRelocations);
		sink("  ");

		// Align
		printSectionCharacteristicsAlign(sink, Characteristics);
		sink("  ");

		// Flags
		printSectionCharacteristicsFlags(sink, Characteristics);
		sink("  ");

		// Name
		formattedWrite(sink, "%s\n", getName(stringTable));
	}
}
static assert(SectionHeader.sizeof == 40);

void printSectionCharacteristicsAlign(scope SinkDelegate sink, u32 Characteristics) {
	if(Characteristics & 0x00F00000) {
		size_t alignment = 1 << (((Characteristics & 0x00F00000) >> 20) - 1);
		formattedWrite(sink, "% 5s", alignment);
	} else formattedWrite(sink, "     ");
}

void printSectionCharacteristicsFlags(scope SinkDelegate sink, u32 Characteristics) {
	if(Characteristics) with(SectionFlags) {
		void printFlag(string str, SectionFlags flag) {
			if(Characteristics & flag) sink(str);
			else sink(" ");
		}
		printFlag("C", SCN_CNT_CODE);
		printFlag("I", SCN_CNT_INITIALIZED_DATA);
		printFlag("U", SCN_CNT_UNINITIALIZED_DATA);
		printFlag("L", SCN_LNK_INFO);
		printFlag("R", SCN_LNK_REMOVE);
		printFlag("M", SCN_LNK_COMDAT);
		printFlag("G", SCN_GPREL);
		printFlag("O", SCN_LNK_NRELOC_OVFL);
		printFlag("D", SCN_MEM_DISCARDABLE);
		printFlag("H", SCN_MEM_NOT_CACHED);
		printFlag("P", SCN_MEM_NOT_PAGED);
		printFlag("S", SCN_MEM_SHARED);
		sink("  ");
		printFlag("R", SCN_MEM_READ);
		printFlag("W", SCN_MEM_WRITE);
		printFlag("X", SCN_MEM_EXECUTE);
	}
}

// Converts name that optionally refers to string table with "/n" format
string nameFromSlashName(const(char)[] name, string stringTable) {
	import vox.lib.string : fromStringz, parseInt;
	if (name[0] == '/') {
		string offsetDecimalString = fromFixedString(name[1..$]);
		usz offset = parseInt(offsetDecimalString);
		return fromStringz(stringTable[offset..$].ptr);
	}
	else return fromFixedString(name);
}

string fromFixedString(const(char)[] fixedStr) {
	foreach_reverse(i, chr; fixedStr)
		if (chr != '\0') return cast(string)fixedStr[0..i+1];
	return null;
}

enum SymbolSectionNumber : i16 {
	/// The symbol record is not yet assigned a section. A
	/// value of zero indicates that a reference to an external
	/// symbol is defined elsewhere. A value of non-zero is a
	/// common symbol with a size that is specified by the
	/// value.
	UNDEFINED = 0,

	/// The symbol has an absolute (non-relocatable) value
	/// and is not an address.
	ABSOLUTE = -1,

	/// The symbol provides general type or debugging
	/// information but does not correspond to a section.
	/// Microsoft tools use this setting along with .file
	/// records (storage class FILE).
	DEBUG = -2,
}

enum CoffSymClass : u8 {
	END_OF_FUNCTION = 0xFF,
	NULL = 0,
	AUTOMATIC = 1,
	EXTERNAL = 2,
	STATIC = 3,
	REGISTER = 4,
	EXTERNAL_DEF = 5,
	LABEL = 6,
	UNDEFINED_LABEL = 7,
	MEMBER_OF_STRUCT = 8,
	ARGUMENT = 9,
	STRUCT_TAG = 10,
	MEMBER_OF_UNION = 11,
	UNION_TAG = 12,
	TYPE_DEFINITION = 13,
	UNDEFINED_STATIC = 14,
	ENUM_TAG = 15,
	MEMBER_OF_ENUM = 16,
	REGISTER_PARAM = 17,
	BIT_FIELD = 18,
	BLOCK = 100,
	FUNCTION = 101,
	END_OF_STRUCT = 102,
	FILE = 103,
	SECTION = 104,
	WEAK_EXTERNAL = 105,
	CLR_TOKEN = 107,
}

struct PeSymbolName {
	@nogc nothrow:
	union
	{
		char[8] ShortName;
		struct {
			u32 Zeroes;
			u32 Offset; // includes 4 size bytes at the beginning of table
		}
	}

	string get(string stringTable) {
		import vox.lib.string : fromStringz;
		if (Zeroes == 0)
			return fromStringz(stringTable[Offset..$].ptr);
		else
			return fromFixedString(ShortName);
	}
}

/// The symbol table in this section is inherited from the traditional COFF format. It is
/// distinct from Microsoft Visual C++® debug information. A file can contain both a
/// COFF symbol table and Visual C++ debug information, and the two are kept
/// separate. Some Microsoft tools use the symbol table for limited but important
/// purposes, such as communicating COMDAT information to the linker. Section
/// names and file names, as well as code and data symbols, are listed in the symbol table.
/// The location of the symbol table is indicated in the COFF header.
/// The symbol table is an array of records, each 18 bytes long. Each record is either a
/// standard or auxiliary symbol-table record. A standard record defines a symbol or
/// name and has the following format.
struct SymbolTableEntry {
	@nogc nothrow:
	align(1):
	/// The name of the symbol, represented by a union
	/// of three structures. An array of 8 bytes is used if
	/// the name is not more than 8 bytes long. For more
	/// information, see section 5.4.1, “Symbol Name Representation.”
	PeSymbolName Name;

	/// The value that is associated with the symbol. The
	/// interpretation of this field depends on
	/// SectionNumber and StorageClass. A typical
	/// meaning is the relocatable address.
	u32 Value;

	/// The signed integer that identifies the section,
	/// using a one-based index into the section table.
	/// Some values have special meaning, as defined in
	/// section 5.4.2, “Section Number Values.”
	i16 SectionNumber; /// See enum SymbolSectionNumber

	/// A number that represents type. Microsoft tools set
	/// this field to 0x20 (function) or 0x0 (not a function).
	/// For more information, see section 5.4.3, “Type
	/// Representation.”
	u16 Type;

	bool isUndefined() { return SectionNumber == SymbolSectionNumber.UNDEFINED; }
	bool isAbsolute() { return SectionNumber == SymbolSectionNumber.ABSOLUTE; }
	bool isDebug() { return SectionNumber == SymbolSectionNumber.DEBUG; }
	bool isFunction() { return Type == 0x20; }
	bool isNonFunction() { return Type == 0x0; }

	/// An enumerated value that represents storage
	/// class. For more information, see section 5.4.4,
	/// “Storage Class.”
	CoffSymClass StorageClass;

	/// The number of auxiliary symbol table entries that
	/// follow this record.
	u8 NumberOfAuxSymbols;

	void print(Sink)(auto ref Sink sink, string stringTable)
	{
		formattedWrite(sink, "  Name: %s\n", Name.get(stringTable));
		//formattedWrite(sink, "  Name: %s %s\n", Name.Zeroes, Name.Offset);
		formattedWrite(sink, "    Value: %08X\n", Value);
		switch(SectionNumber)
		{
			case -2: formattedWrite(sink, "    Section: Debug\n"); break;
			case -1: formattedWrite(sink, "    Section: Absolute\n"); break;
			case  0: formattedWrite(sink, "    Section: Undefined\n"); break;
			default: formattedWrite(sink, "    Section: %s\n", SectionNumber);
		}
		formattedWrite(sink, "    Type: %s\n", Type);
		formattedWrite(sink, "    Storage class: %s\n", StorageClass);
		formattedWrite(sink, "    Number of aux symbols: %s\n", NumberOfAuxSymbols);
	}
}
static assert(SymbolTableEntry.sizeof == 18);
