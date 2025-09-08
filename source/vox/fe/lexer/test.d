/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.fe.lexer.test;

import vox.lib;
import vox.tests.infra;
import vox.fe.lexer;
import vox.fe.lexer.token_type;

@Test
void test_lexer(ref SimpleTestContext c) {
	void test(string source, string expectedMatch, TokenType expectedToken,
		string file = __FILE__, int line = __LINE__)
	{
		auto lexer = Lexer(source);
		auto tok = lexer.nextToken;
		auto match = tok.getTokenString(source);

		if (match == expectedMatch && tok.tok == expectedToken) return;

		writefln("Lexer test failed %s", line);
		writefln("  Expected:\n    token: %s\n    match: %s\n  Got: \n    token: %s\n    match: %s",
			expectedToken, expectedMatch, tok.tok, match);
		panic(line, file, 0, "Unexpected token");
	}

	test("\0", "", TokenType.eoi);
	test("\"\"\0", "\"\"", TokenType.lit_string);
	test("\'\'\0", "\'\'", TokenType.lit_char);

	test("//\n\0", "//\n", TokenType.comment);
	test("//a\n\0", "//a\n", TokenType.comment);
	test("//\0", "//", TokenType.comment);
	test("//a\0", "//a", TokenType.comment);
	test("/*\0", "/*", TokenType.inval_comment);
	test("/**\0", "/**", TokenType.inval_comment);
	test("/**/\0", "/**/", TokenType.comment);
	test("/*a*/\0", "/*a*/", TokenType.comment);
	test("/*\na*/\0", "/*\na*/", TokenType.comment);

	test("0\0", "0", TokenType.lit_int_dec);
	test("1\0", "1", TokenType.lit_int_dec);
	test("9\0", "9", TokenType.lit_int_dec);
	test("0_\0", "0", TokenType.lit_int_dec);
	test("1_\0", "1_", TokenType.lit_int_dec);
	test("9_\0", "9_", TokenType.lit_int_dec);

	test("0x\0", "0x", TokenType.invalid);
	test("0x_\0", "0x_", TokenType.invalid);
	test("0xz\0", "0x", TokenType.invalid);
	test("0x_0\0", "0x_0", TokenType.lit_int_hex);
	test("0x0_\0", "0x0_", TokenType.lit_int_hex);
	test("0x0\0", "0x0", TokenType.lit_int_hex);
	test("0xf\0", "0xf", TokenType.lit_int_hex);
	test("0xF\0", "0xF", TokenType.lit_int_hex);

	test("0b\0", "0b", TokenType.invalid);
	test("0b2\0", "0b", TokenType.invalid);
	test("0b_\0", "0b_", TokenType.invalid);
	test("0b_0\0", "0b_0", TokenType.lit_int_bin);
	test("0b0_\0", "0b0_", TokenType.lit_int_bin);
	test("0b0\0", "0b0", TokenType.lit_int_bin);
	test("0b1\0", "0b1", TokenType.lit_int_bin);
	test("0b10\0", "0b10", TokenType.lit_int_bin);

	test("&\0", "&", TokenType.and);
	test("&&\0", "&&", TokenType.and2);
	test("&=\0", "&=", TokenType.and_eq);
	test("@\0", "@", TokenType.at);
	test("\\0", "\\", TokenType.backslash);
	test(":\0", ":", TokenType.colon);
	test(",\0", ",", TokenType.comma);
	test(".\0", ".", TokenType.dot);
	test("..\0", "..", TokenType.dot2);
	test("...\0", "...", TokenType.dot3);
	test("=\0", "=", TokenType.eq);
	test("==\0", "==", TokenType.eq2);
	test(">\0", ">", TokenType.more);
	test(">=\0", ">=", TokenType.more_eq);
	test(">>\0", ">>", TokenType.more2);
	test(">>=\0", ">>=", TokenType.more2_eq);
	test(">>>\0", ">>>", TokenType.more3);
	test(">>>=\0", ">>>=", TokenType.more3_eq);
	test("<\0", "<", TokenType.less);
	test("<=\0", "<=", TokenType.less_eq);
	test("<<\0", "<<", TokenType.less2);
	test("<<=\0", "<<=", TokenType.less2_eq);
	test("-\0", "-", TokenType.minus);
	test("-=\0", "-=", TokenType.minus_eq);
	test("--\0", "--", TokenType.minus2);
	test("!\0", "!", TokenType.not);
	test("!=\0", "!=", TokenType.not_eq);
	test("|\0", "|", TokenType.or);
	test("|=\0", "|=", TokenType.or_eq);
	test("||\0", "||", TokenType.or2);
	test("%\0", "%", TokenType.percent);
	test("%=\0", "%=", TokenType.percent_eq);
	test("+\0", "+", TokenType.plus);
	test("+=\0", "+=", TokenType.plus_eq);
	test("++\0", "++", TokenType.plus2);
	test("?\0", "?", TokenType.question);
	test(";\0", ";", TokenType.semicolon);
	test("/\0", "/", TokenType.slash);
	test("/=\0", "/=", TokenType.slash_eq);
	test("*\0", "*", TokenType.star);
	test("*=\0", "*=", TokenType.star_eq);
	test("~\0", "~", TokenType.tilde);
	test("~=\0", "~=", TokenType.tilde_eq);
	test("^\0", "^", TokenType.xor);
	test("^=\0", "^=", TokenType.xor_eq);
	test("(\0", "(", TokenType.lparen);
	test(")\0", ")", TokenType.rparen);
	test("[\0", "[", TokenType.lbracket);
	test("]\0", "]", TokenType.rbracket);
	test("{\0", "{", TokenType.lcurly);
	test("}\0", "}", TokenType.rcurly);

	test("alias\0", "alias", TokenType.kw_alias);
	test("auto\0", "auto", TokenType.kw_auto);
	test("bool\0", "bool", TokenType.kw_bool);
	test("break\0", "break", TokenType.kw_break);
	test("cast\0", "cast", TokenType.kw_cast);
	test("continue\0", "continue", TokenType.kw_continue);
	test("do\0", "do", TokenType.kw_do);
	test("else\0", "else", TokenType.kw_else);
	test("enum\0", "enum", TokenType.kw_enum);
	test("f32\0", "f32", TokenType.kw_f32);
	test("f64\0", "f64", TokenType.kw_f64);
	test("false\0", "false", TokenType.kw_false);
	test("for\0", "for", TokenType.kw_for);
	test("function\0", "function", TokenType.kw_function);
	test("i16\0", "i16", TokenType.kw_i16);
	test("i32\0", "i32", TokenType.kw_i32);
	test("i64\0", "i64", TokenType.kw_i64);
	test("i8\0", "i8", TokenType.kw_i8);
	test("if\0", "if", TokenType.kw_if);
	test("import\0", "import", TokenType.kw_import);
	test("isz\0", "isz", TokenType.kw_isz);
	test("module\0", "module", TokenType.kw_module);
	test("noreturn\0", "noreturn", TokenType.kw_noreturn);
	test("null\0", "null", TokenType.kw_null);
	test("return\0", "return", TokenType.kw_return);
	test("struct\0", "struct", TokenType.kw_struct);
	test("switch\0", "switch", TokenType.kw_switch);
	test("true\0", "true", TokenType.kw_true);
	test("u16\0", "u16", TokenType.kw_u16);
	test("u32\0", "u32", TokenType.kw_u32);
	test("u64\0", "u64", TokenType.kw_u64);
	test("u8\0", "u8", TokenType.kw_u8);
	test("union\0", "union", TokenType.kw_union);
	test("usz\0", "usz", TokenType.kw_usz);
	test("void\0", "void", TokenType.kw_void);
	test("while\0", "while", TokenType.kw_while);

	test("#\0", "#", TokenType.invalid);
	test("#a\0", "#a", TokenType.invalid);

	test("#if\0", "#if", TokenType.hash_if);
	test("#version\0", "#version", TokenType.hash_version);
	test("#inline\0", "#inline", TokenType.hash_inline);
	test("#assert\0", "#assert", TokenType.hash_assert);
	test("#foreach\0", "#foreach", TokenType.hash_foreach);
	test("#alias\0", "#alias", TokenType.hash_alias);
	test("#type\0", "#type", TokenType.hash_type);

	test("$alias\0", "$alias", TokenType.dollar_alias);
	test("$type\0", "$type", TokenType.dollar_type);

	test("$_\0", "$_", TokenType.dollar_id);
	test("$1\0", "$", TokenType.invalid);
	test("_\0", "_", TokenType.id);
}
