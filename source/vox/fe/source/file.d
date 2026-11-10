/// Copyright: Copyright (c) 2026 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.fe.source.file;

import vox.lib;
import vox.fe.ast.decl.module_;

@nogc nothrow:

// Files can be physical or virtual
// Files can be part of a parent file (.har/.zip)
struct FileInfo {
	const(char)[] name;
	// Offset into bufs.file
	u32 offset;
	// Doesn't include zero bytes at the end
	u32 length;
	// AST node
	ModuleDecl node;
}
