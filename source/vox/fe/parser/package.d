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

	string getTokenString() {
		if (tok.type == TokenType.eoi)
			return "end of file";
		else
			return cast(string)tok.getTokenString(context.bufs.sources.data);
	}

	Result!void parseModule(ref FileInfo file) {
		lexer.input = context.bufs.sources.bufPtr;
		lexer.position = file.offset;
		lexer.line = 0;
		lexer.column = 0;
		nextToken;

		//return Result!void();

		if (tok.type == TokenType.semicolon) {
			return context.makeError!void(tok.span,
				"Expected %s, got %s",
				"declaration",
				getTokenString());
		}
		//return Result!void();
		//writefln("--- %s at %s\n%s", file.name, file.offset, lexer.input[file.offset..file.offset+file.length]);
		//return expectIdentifier().Result!void;
		//while (tok.type != TokenType.eoi) {
		//	if (tok.type == TokenType.eoi) break;
		//	parse_declaration();
		//}

		//while(true) {
		//	auto tok = lexer.nextToken;
		//	//writefln("  %s", cast(uint)tok.tok);
		//	if (tok.tok == TokenType.eoi) break;
		//}
		AstNodes items;
		return parse_declarations(items, TokenType.eoi);
	}

	Result!void expect(TokenType type, string what, string afterWhat = null) {
		if (tok.type != type) {
			if (afterWhat)
				return context.makeError!void(tok.span, "Expected %s after %s, got %s", what, afterWhat, getTokenString());
			else
				return context.makeError!void(tok.span, "Expected %s, got %s", what, getTokenString());
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

	Result!void parse_declarations(ref AstNodes declarations, TokenType until) { // <declaration>*
		while (tok.type != until) {
			if (tok.type == TokenType.eoi) break;
			auto res = parse_declaration(declarations);
			if (res.isError) return res;
		}
		return Result!void();
	}

	Result!void parse_declaration(ref AstNodes items) { // <declaration> ::= <var_declaration>
		switch(tok.type) with(TokenType) {
			case kw_i32: {
				nextToken; // skip i32

 				auto res1 = expectIdentifier("i32");
 				if (res1.isError) {
					return Result!void(res1);
				}
				auto id = res1.data;

 				auto res2 = expectAndConsume(TokenType.semicolon, ";", "identifier");
				if (res2.isError) {
					return Result!void(res2);
				}

 				return Result!void();
 			}

 			default:
 				return context.makeError!void(tok.span, "TODO: %s", getTokenString());
		}
	}
}

struct AstNode {
	uint data;
}

alias AstNodes = Array!AstNode;

struct ModuleDeclNode {

}
