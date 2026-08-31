/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.fe.source.location;

struct Position {
	// Offset into Buffers.sources
	// Zero denotes no position
	uint offset;
}

// A slice of a source code
struct Span {
	@nogc nothrow:

	Position start;
	Position end;

	size_t length() inout => end.offset - start.offset;
}
