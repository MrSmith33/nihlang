/// Copyright: Copyright (c) 2026 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
module vox.fe.ast.scope_;

import vox.lib;
import vox.fe;
import vox.context;

///
struct Scope {
	@nogc nothrow:
	///
	AstNodeMap symbolMap;
	/// Imported modules
	AstNodes imports;
	///
	AstIndex parentModule;
	///
	AstIndex parentScope;
	/// This node is owner of all the definitions inside of this scope
	AstIndex ownerSymbol;
	///
	ScopeKind kind;

	AstIndex findSymbol(Name name, ref VoxContext context) {
		return symbolMap.get(name, AstIndex.init);
	}

	/// Constructs and inserts symbol with id
	Result!void insertSymbol(Name name, AstIndex nodeIndex, ref VoxContext c) {
		bool wasCreated;
		auto res = symbolMap.getOrCreate(c.bufs.arrayArena, name, wasCreated, nodeIndex);
		if (res.isError) return Result!void.fromError(res);
		if (!wasCreated) {
			AstIndex* node = res.data;
			//c.error(node.location,
			//	"declaration `%s` is already defined at %s",
			//	c.getString(name), FmtSrcLoc(s.get_node(c).loc, c));
		}
		return Result!void.init;
	}
}

struct ScopeIndex {
	@nogc nothrow:

	AstIndex index;
	alias index this;

	// null scope index is treated as empty scope and results in null AstIndex
	AstIndex findSymbol(Name name, ref VoxContext context) {
		if (isUndefined) return AstIndex.init;
		ref Scope sc = context.getAst!Scope(index);
		return sc.symbolMap.get(name, AstIndex.init);
	}

	Result!void insertSymbol(Name name, AstIndex nodeIndex, ref VoxContext context) {
		assert(isDefined, "scope is undefined");
		ref Scope sc = context.getAst!Scope(index);
		return sc.insertSymbol(name, nodeIndex, context);
	}
}

enum ScopeKind : ubyte {
	no_scope, // scope created by @attr{} or by #version or #if or #foreach
	local,  // function
	member, // struct, union, enum
	global, // module
}
