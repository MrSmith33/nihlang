/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.formats.executable;

import vox.lib;
import vox.lib.formats.pecoff.definitions;

struct CoffExecutable {
	@nogc nothrow:

	DosHeader dosHeader;
	DosStub dosStub;
	PeSignature peSignature;
	CoffFileHeader coffFileHeader;
	OptionalHeader optionalHeader;
	SectionHeader[] sectionHeaders;
	string stringTable;

	usz dosStubOffset;
	usz peSignatureOffset;
	usz coffFileHeaderOffset;
	usz optionalHeaderOffset;

	void write(ref VoxAllocator allocator, ref Array!u8 sink) {
		dosHeader.write(allocator, sink);
		dosStubOffset = dosStub.write(allocator, sink);
		peSignatureOffset = peSignature.write(allocator, sink);
		coffFileHeaderOffset = coffFileHeader.write(allocator, sink);
		optionalHeaderOffset = optionalHeader.write(allocator, sink);
	}

	void parse(u8[] data) {
		import vox.lib.formats.slicer : FileDataSlicer;

		auto slicer = FileDataSlicer(data);
		dosHeader = *slicer.getPtrTo!DosHeader;

		dosStub.data = slicer.getArrayOfToOffset!u8(dosHeader.e_lfanew);
		dosStubOffset = slicer.offsetOf(dosStub.data);

		auto peSignaturePtr = slicer.getPtrTo!PeSignature;
		peSignature = *peSignaturePtr;
		peSignatureOffset = slicer.offsetOf(peSignaturePtr);
		enforce(*peSignaturePtr == PeSignature.init, "Unknown PE signature %s offset %s",
			peSignaturePtr.signature.EscapedString, peSignatureOffset);

		auto coffFileHeaderPtr = slicer.getPtrTo!CoffFileHeader;
		coffFileHeader = *coffFileHeaderPtr;
		coffFileHeaderOffset = slicer.offsetOf(coffFileHeaderPtr);

		if (coffFileHeader.PointerToSymbolTable != 0) {
			auto symbolTableSlicer = FileDataSlicer(data, coffFileHeader.PointerToSymbolTable);
			auto symbolTable = symbolTableSlicer.getArrayOf!SymbolTableEntry(coffFileHeader.NumberOfSymbols);
			u32 stringTableSize = *symbolTableSlicer.getPtrTo!u32();
			assert(stringTableSize >= 4);
			symbolTableSlicer.fileCursor -= 4; // String table includes the u32 size
			stringTable = cast(string)slicer.getArrayOf!char(stringTableSize);
		}

		auto optHeaderPtr = slicer.getPtrTo!OptionalHeader;
		optionalHeader = *optHeaderPtr;
		optionalHeaderOffset = slicer.offsetOf(optHeaderPtr);

		sectionHeaders = slicer.getArrayOf!SectionHeader(coffFileHeader.NumberOfSections);
	}

	void toString(scope SinkDelegate sink, FormatSpec spec) const {
		formattedWrite(sink, "DOS header (offset 0, size %s):\n%s", dosHeader.fileSize, dosHeader);
		formattedWrite(sink, "DOS stub (offset %s, size %s)\n%s", dosStubOffset, dosStub.fileSize, dosStub);
		formattedWrite(sink, "PE signature (offset %s, size %s):\n%s", peSignatureOffset, peSignature.fileSize, peSignature);
		formattedWrite(sink, "COFF header (offset %s, size %s):\n%s", coffFileHeaderOffset, coffFileHeader.fileSize, coffFileHeader);
		formattedWrite(sink, "Optional header (offset %s, size %s):\n%s", optionalHeaderOffset, optionalHeader.fileSize, optionalHeader);
		formattedWrite(sink, "Section table:\n");
		SectionHeader.printTableHeader(sink);
		foreach (i, header; sectionHeaders) {
			header.print(sink, i, stringTable);
		}
	}
}
