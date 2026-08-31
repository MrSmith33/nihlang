/// Copyright: Copyright (c) 2026 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
module vox.fe.parser;

import vox.lib;
import vox.source;
import vox.context;

struct Parser {
	@nogc nothrow:

	import vox.fe.lexer;
	VoxContext* context;
	Lexer lexer;
	Token tok;

	void nextToken() {
		do {
			tok = lexer.nextToken();
		}
		while (tok.type == TokenType.comment);
	}

	void parseModule(ref FileInfo file) {
		lexer.input = context.bufs.sources.bufPtr;
		lexer.position = file.offset;
		lexer.line = 0;
		lexer.column = 0;
		nextToken;

		//writefln("--- %s at %s\n%s", file.name, file.offset, lexer.input[file.offset..file.offset+file.length]);
		expectIdentifier();
		//while (tok.type != TokenType.eoi) {
		//	if (tok.type == TokenType.eoi) break;
		//	parse_declaration();
		//}

		//while(true) {
		//	auto tok = lexer.nextToken;
		//	//writefln("  %s", cast(uint)tok.tok);
		//	if (tok.tok == TokenType.eoi) break;
		//}
	}

	Result!void expect(TokenType type, string what, string afterWhat = null) {
		if (tok.type != type) {
			const(char)[] tokenString = tok.getTokenString(context.bufs.sources.data);
			if (afterWhat)
				return context.makeError!void(tok.span, "Expected %s after %s, got %s", what, afterWhat, cast(string)tokenString);
			else
				return context.makeError!void(tok.span, "Expected %s, got %s", what, cast(string)tokenString);
		}
		return Result!void();
	}

	Result!void expectAndConsume(TokenType type, string what, string afterWhat = null) {
		auto res = expect(type, what, afterWhat);
		if (res.isError) {
			return res;
		}
		nextToken;
		return Result!void();
	}

	Name makeIdentifier(Token tok) {
		const(char)[] str = tok.getTokenString(context.bufs.sources.data);
		return context.bufs.nameMap.getOrReg(context.bufs.arrayArena, str);
	}

	Result!Name expectIdentifier(string after = null) {
		Span span = tok.span;
		auto res = expectAndConsume(TokenType.id, "identifier", after);
		if (res.isError) {
			return Result!Name(res);
		}
		Name id = makeIdentifier(tok);
		return Result!Name(id);
	}

	void parse_declaration() {

	}

	/*void parse_declaration(ref AstNodes items) // <declaration> ::= <func_declaration> / <var_declaration> / <struct_declaration>
	{
		version(print_parse) auto s1 = scop("parse_declaration %s", loc);

		switch(tok.type) with(TokenType)
		{
			kw_i32:
				nextToken; // skip i32
 				// <func_declaration> / <var_declaration>
 				break;

 			default:
 				// Error
				return;
		}
		assert(false);
	}*/
}

struct AstNode {
	uint data;
}

alias AstNodes = Array!AstNode;

struct ModuleDeclNode {

}
