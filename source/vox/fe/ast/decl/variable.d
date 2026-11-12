/// Copyright: Copyright (c) 2026 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
module vox.fe.ast.decl.variable;

import vox.context;
import vox.lib;
import vox.fe;
import vox.be;

struct VariableDecl {
	@nogc nothrow:
	NameWithPos name;
	ScopeIndex parentScope;

	// For global variables
	LinkIndex symIndex;

	Result!void register_name(AstIndex nodeIndex, ref VoxContext context) {
		ref Scope sc = context.getScope(parentScope);
		ObjectSymbol sym = {
			kind : ObjectSymbolKind.isLocal,
			moduleIndex : context.getAst!ModuleDecl(sc.parentModule).symIndex,
			flags : ObjectSymbolFlags.isMutable,
		};

		symIndex = context.bufs.objSymTab.addSymbol(sym);

		return sc.insertSymbol(name.name, nodeIndex, context);
	}
}
