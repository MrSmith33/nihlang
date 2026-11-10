/// Copyright: Copyright (c) 2026 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
module vox.fe.ast.decl.module_;

import vox.lib;
import vox.context;
import vox.fe;

struct ModuleDecl {
	@nogc nothrow:
	AstNodes declarations;
	ScopeIndex memberScope;

	Result!void register_names_nested(ref VoxContext context) {
		foreach(AstIndex decl; declarations) {
			ref varDecl = context.getAst!VariableDecl(decl);
			auto res = memberScope.insertSymbol(varDecl.name.name, decl, context);
			if (res.isError) return Result!void.fromError(res);
		}
		return Result!void.init;
	}
}
