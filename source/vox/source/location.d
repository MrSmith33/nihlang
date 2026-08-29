/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.fe.source.location;

struct Position {
	// Offset into Buffers.sources
	// Zero denotes no position
	uint offset;
}

struct Location {
	Position start;
	Position end;
}
