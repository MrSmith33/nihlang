/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.fe.lexer.generator;

import core.bitop;
import std.stdio;
import std.range;
import std.format;
import std.algorithm;

void main() {
	auto ops = [
		Keyword("and", "&"),
		Keyword("and2", "&&"),
		Keyword("and_eq", "&="),
		Keyword("at", "@"),
		Keyword("backslash", "\\"),
		Keyword("colon", ":"),
		Keyword("comma", ","),
		Keyword("dot", "."),
		Keyword("dot2", ".."),
		Keyword("dot3", "..."),
		Keyword("eq", "="),
		Keyword("eq2", "=="),
		Keyword("more", ">"),
		Keyword("more_eq", ">="),
		Keyword("more2", ">>"),
		Keyword("more2_eq", ">>="),
		Keyword("more3", ">>>"),
		Keyword("more3_eq", ">>>="),
		Keyword("less", "<"),
		Keyword("less_eq", "<="),
		Keyword("less2", "<<"),
		Keyword("less2_eq", "<<="),
		Keyword("minus", "-"),
		Keyword("minus_eq", "-="),
		Keyword("minus2", "--"),
		Keyword("not", "!"),
		Keyword("not_eq", "!="),
		Keyword("or", "|"),
		Keyword("or_eq", "|="),
		Keyword("or2", "||"),
		Keyword("percent", "%"),
		Keyword("percent_eq", "%="),
		Keyword("plus", "+"),
		Keyword("plus_eq", "+="),
		Keyword("plus2", "++"),
		Keyword("question", "?"),
		Keyword("semicolon", ";"),
		// added together with the comment
		// Keyword("slash", "/"),
		// Keyword("slash_eq", "/="),
		Keyword("star", "*"),
		Keyword("star_eq", "*="),
		Keyword("tilde", "~"),
		Keyword("tilde_eq", "~="),
		Keyword("xor", "^"),
		Keyword("xor_eq", "^="),
		Keyword("lparen", "("),
		Keyword("rparen", ")"),
		Keyword("lbracket", "["),
		Keyword("rbracket", "]"),
		Keyword("lcurly", "{"),
		Keyword("rcurly", "}"),
	];

	Identifier id = {
		enum_name: "id",
		comment: "[a-zA-Z_] [a-zA-Z_0-9]*",
		firstChar: CharClass.id1,
		secondChar: CharClass.id2,
		keywords: [
			Keyword("kw_alias", "alias"),
			Keyword("kw_auto", "auto"),
			Keyword("kw_bool", "bool"),
			Keyword("kw_break", "break"),
			Keyword("kw_cast", "cast"),
			Keyword("kw_continue", "continue"),
			Keyword("kw_do", "do"),
			Keyword("kw_else", "else"),
			Keyword("kw_enum", "enum"),
			Keyword("kw_f32", "f32"),
			Keyword("kw_f64", "f64"),
			Keyword("kw_false", "false"),
			Keyword("kw_for", "for"),
			Keyword("kw_function", "function"),
			Keyword("kw_i16", "i16"),
			Keyword("kw_i32", "i32"),
			Keyword("kw_i64", "i64"),
			Keyword("kw_i8", "i8"),
			Keyword("kw_if", "if"),
			Keyword("kw_import", "import"),
			Keyword("kw_isz", "isz"),
			Keyword("kw_module", "module"),
			Keyword("kw_noreturn", "noreturn"),
			Keyword("kw_null", "null"),
			Keyword("kw_return", "return"),
			Keyword("kw_struct", "struct"),
			Keyword("kw_switch", "switch"),
			Keyword("kw_true", "true"),
			Keyword("kw_u16", "u16"),
			Keyword("kw_u32", "u32"),
			Keyword("kw_u64", "u64"),
			Keyword("kw_u8", "u8"),
			Keyword("kw_union", "union"),
			Keyword("kw_usz", "usz"),
			Keyword("kw_void", "void"),
			Keyword("kw_while", "while"),
		]
	};

	Identifier hashId = {
		enum_name: null,
		sigil: CharClass.make(`#`),
		firstChar: CharClass.id1,
		secondChar: CharClass.id2,
		keywords: [
			Keyword("hash_if", "#if"),
			Keyword("hash_version", "#version"),
			Keyword("hash_inline", "#inline"),
			Keyword("hash_assert", "#assert"),
			Keyword("hash_foreach", "#foreach"),
			Keyword("hash_alias", "#alias"),
			Keyword("hash_type", "#type"),
		],
	};

	Identifier dollarId = {
		enum_name: "dollar_id",
		comment: "$ [a-zA-Z_] [a-zA-Z_0-9]*",
		sigil: CharClass.make(`$`),
		firstChar: CharClass.id1,
		secondChar: CharClass.id2,
		keywords: [
			Keyword("dollar_alias", "$alias"),
			Keyword("dollar_type", "$type"),
		],
	};

	Gen gen;
	gen.begin;

	gen.addOperators(ops);
	gen.addId(id);
	gen.addId(hashId);
	gen.addId(dollarId);

	gen.end;
	// gen.print;
	gen.generateTables();
}

struct Identifier {
	// Token when no keyword matches
	// If empty will go to invalid
	string enum_name;
	string comment;
	CharClass sigil;
	CharClass firstChar;
	CharClass secondChar;
	Keyword[] keywords;
}

struct Keyword {
	string enum_name;
	string token;
}

struct Node {
	string name;
	string token;
	string comment;
	bool isTerminal;
	uint stateIndex;
	Node*[256] suffixes;
}

struct Gen {
	Node* start;
	Node* invalid;
	Node* eoi;
	Node*[] nonTerminals;
	Node*[] terminals;

	void begin() {
		// start has a separate array, no need to put it in nonTerminals
		start = new Node("start");
		invalid = addTerminal(new Node("invalid", isTerminal: true));
		eoi = addTerminal(new Node("eoi", isTerminal: true));

		// string literal
		auto lit_string = addTerminal(new Node("lit_string", `""`, `""`, isTerminal: true));
		auto i_quote2 = addNonterminal(new Node("\"", `""`));
		auto i_quote2_esc = addNonterminal(new Node("\"\\", `""`));
		auto i_lit_string = addNonterminal(new Node("\"\"", `""`));

		fill(start, CharClass.make("\""), i_quote2);
		fill(i_quote2, CharClass.all, i_quote2);
		fill(i_quote2, CharClass.make("\\"), i_quote2_esc);
		fill(i_quote2_esc, CharClass.all, i_quote2);
		fill(i_quote2, CharClass.make("\""), i_lit_string);
		fill(i_lit_string, CharClass.all, lit_string);
		fill(i_quote2, CharClass.make("\0"), invalid);
		fill(i_quote2_esc, CharClass.make("\0"), invalid);

		// char literal
		auto lit_char = addTerminal(new Node("lit_char", `''`, `''`, isTerminal: true));
		auto i_quote = addNonterminal(new Node("'", `''`));
		auto i_quote_esc = addNonterminal(new Node("'\\", `''`));
		auto i_lit_char = addNonterminal(new Node("''", `''`));

		fill(start, CharClass.make("'"), i_quote);
		fill(i_quote, CharClass.all, i_quote);
		fill(i_quote, CharClass.make("\\"), i_quote_esc);
		fill(i_quote_esc, CharClass.all, i_quote);
		fill(i_quote, CharClass.make("'"), i_lit_char);
		fill(i_lit_char, CharClass.all, lit_char);
		fill(i_quote, CharClass.make("\0"), invalid);
		fill(i_quote_esc, CharClass.make("\0"), invalid);

		// Division
		//Keyword("slash", "/"),
		auto slash = addTerminal(new Node("slash", "/", "/", isTerminal: true));
		auto slash_eq = addTerminal(new Node("slash_eq", "/=", "/=", isTerminal: true));
		auto i_slash = addNonterminal(new Node("slash", "/"));
		auto i_slash_eq = addNonterminal(new Node("slash_eq", "/="));
		fill(i_slash, CharClass.all, slash);
		fill(i_slash, CharClass.make("="), i_slash_eq);
		fill(i_slash_eq, CharClass.all, slash_eq);

		// comment
		auto comment = addTerminal(new Node("comment", "//", "// /**/", isTerminal: true));
		auto inval_comment = addTerminal(new Node("inval_comment", "/*", "/* /**", isTerminal: true));
		// i_slash targets will be filled by addOperators for / and /=
		auto i_slash_star = addNonterminal(new Node("slash_star", "/*"));
		auto i_slash_star2 = addNonterminal(new Node("slash_star2", "/**"));
		auto i_slash2 = addNonterminal(new Node("slash2", "//"));
		auto i_comment = addNonterminal(new Node("comment", "//"));
		fill(start, CharClass.make("/"), i_slash);
		fill(i_slash, CharClass.make("/"), i_slash2);
		fill(i_slash2, CharClass.all, i_slash2);
		// don't consume \0
		fill(i_slash2, CharClass.make("\0"), comment);
		// consume \n
		fill(i_slash2, CharClass.make("\n"), i_comment);
		fill(i_comment, CharClass.all, comment);

		// multiline comment
		fill(i_slash, CharClass.make("*"), i_slash_star);
		fill(i_slash_star, CharClass.all, i_slash_star);
		fill(i_slash_star, CharClass.make("*"), i_slash_star2);
		fill(i_slash_star, CharClass.make("\0"), inval_comment);
		fill(i_slash_star2, CharClass.all, i_slash_star);
		fill(i_slash_star2, CharClass.make("*"), i_slash_star2);
		fill(i_slash_star2, CharClass.make("/"), i_comment);
		fill(i_slash_star2, CharClass.make("\0"), inval_comment);

		// numbers
		// lit_int_dec |  0|[1-9][0-9_]*
		// lit_int_hex |  ("0b"|"0B")_*[01_]+
		// lit_int_bin |  ("0x"|"0X")_*[0-9A-Fa-f_]+
		auto lit_int_dec = addTerminal(new Node("lit_int_dec", comment: "0|([1-9][0-9_]*)", isTerminal: true));
		auto lit_int_hex = addTerminal(new Node("lit_int_hex", comment: "0[xX][0-9A-Fa-f][0-9A-Fa-f_]*", isTerminal: true));
		auto lit_int_bin = addTerminal(new Node("lit_int_bin", comment: "0[bB][01][01_]*", isTerminal: true));
		auto i_dig1_0 = addNonterminal(new Node("i_dig1_0", "0"));
		auto i_dig2_b = addNonterminal(new Node("i_dig2_b", "0b"));
		auto i_dig3_b = addNonterminal(new Node("i_dig3_b", "0b_"));
		auto i_dig4_b = addNonterminal(new Node("i_dig4_b", "0b0"));
		auto i_dig2_x = addNonterminal(new Node("i_dig2_x", "0x"));
		auto i_dig3_x = addNonterminal(new Node("i_dig3_x", "0x_"));
		auto i_dig4_x = addNonterminal(new Node("i_dig4_x", "0x0"));
		auto i_dig2_d = addNonterminal(new Node("i_dig4_x", "0x0"));
		fill(start, CharClass.make("0"), i_dig1_0);
		fill(i_dig1_0, CharClass.all, lit_int_dec);
		fill(i_dig1_0, CharClass.make("bB"), i_dig2_b);
		fill(i_dig2_b, CharClass.all, invalid);
		fill(i_dig2_b, CharClass.make("01"), i_dig4_b);
		fill(i_dig4_b, CharClass.all, lit_int_bin);
		fill(i_dig4_b, CharClass.make("_01"), i_dig4_b);
		fill(i_dig2_b, CharClass.make("_"), i_dig3_b);
		fill(i_dig3_b, CharClass.all, invalid);
		fill(i_dig3_b, CharClass.make("_"), i_dig3_b);
		fill(i_dig3_b, CharClass.make("01"), i_dig4_b);

		fill(i_dig1_0, CharClass.make("xX"), i_dig2_x);
		fill(i_dig2_x, CharClass.all, invalid);
		fill(i_dig2_x, CharClass.make("0123456789abcdefABCDEF"), i_dig4_x);
		fill(i_dig4_x, CharClass.all, lit_int_hex);
		fill(i_dig4_x, CharClass.make("_0123456789abcdefABCDEF"), i_dig4_x);
		fill(i_dig2_x, CharClass.make("_"), i_dig3_x);
		fill(i_dig3_x, CharClass.all, invalid);
		fill(i_dig3_x, CharClass.make("_"), i_dig3_x);
		fill(i_dig3_x, CharClass.make("0123456789abcdefABCDEF"), i_dig4_x);

		fill(start, CharClass.make("123456789"), i_dig2_d);
		fill(i_dig2_d, CharClass.all, lit_int_dec);
		fill(i_dig2_d, CharClass.make("_0123456789"), i_dig2_d);
	}

	void end() {
		foreach(i, node; nonTerminals) {
			node.stateIndex = cast(uint)i;
		}
		foreach(i, node; terminals) {
			node.stateIndex = cast(uint)i;
		}
		fillEmpty(start, CharClass.make("\0"), eoi);
		fillEmpty(start, CharClass.all, invalid);
	}

	Node* addNonterminal(Node* node) {
		nonTerminals ~= node;
		return node;
	}

	Node* addTerminal(Node* node) {
		terminals ~= node;
		return node;
	}

	void print() {
		auto printFor = CharClass.make("1\0\n/a"); // only print a few columns
		// auto printFor = CharClass.all;

		writef("                |");
		foreach(char at; printFor) {
			if (at in CharClass.printable)
				writef(" % 2s", at);
			else
				writef(" %02X", cast(uint)at);
		}
		writeln;

		void printAbs(Node* node, Node* target) {
			writef(" %02X", target.stateIndex);
		}

		void printRel(Node* node, Node* target) {
			if (node.stateIndex <= target.stateIndex)
				writef(" %02X", target.stateIndex - node.stateIndex);
			else
				writef("-%02X", node.stateIndex - target.stateIndex);
		}

		void printCheck(Node* node, Node* target) {
			auto delta = target.stateIndex - node.stateIndex;
			if (target.isTerminal) {
				write("  t");
			} else if (target.stateIndex < node.stateIndex) {
				write("  n");
			} else if ((delta & 0b0111_1111) != delta) {
				write("  M");
			} else {
				write(" ok");
			}
		}

		void printFinal(Node* node, Node* target) {
			auto delta = target.stateIndex - node.stateIndex;
			if (node is start) {
				write(" ");
				writef(startTerminalFmt(), target.stateIndex | startTerminalBit(target));
			} else if (target.isTerminal) {
				writef(" %02X", target.stateIndex | 0b1000_0000);
			} else {
				// absolute, for debugging
				writef(" %02X", target.stateIndex);
				// relative, as it is stored in table (but table has bias)
				// writef(" %02X", target.stateIndex - node.stateIndex);
			}
		}

		void printNum(Node* node, Node* target) {
			// printAbs(node, target);
			// printRel(node, target);
			// printCheck(node, target);
			printFinal(node, target);
		}

		foreach(node; chain([start], nonTerminals, terminals)) {
			writef("%02X % 12s |", node.stateIndex | (node.isTerminal ? 0b1000_0000 : 0), node.name);
			foreach(char at; printFor) {
				Node* target = node.suffixes[at];

				if (node.isTerminal)
					write("   ");
				else if (target)
					printNum(node, target);
				else
					write(" ??");
			}
			writeln;
		}
	}

	string startTerminalFmt() {
		if (nonTerminals.length <= 127) return "%02X";
		return "%04X";
	}

	uint startTerminalBit(Node* node) {
		if (!node.isTerminal) return 0;
		if (nonTerminals.length <= 127) return 0b1000_0000;
		return 0b1000_0000_0000_0000;
	}

	void generateTables() {
		writeTokenFile();
		writeLexerFile();
	}
	void writeTokenFile() {
		auto file = File(`token_type.d`, "w");
		auto sink = file.lockingBinaryWriter;

		sink.formattedWrite("/// Copyright: Copyright (c) 2025 Andrey Penechko\n");
		sink.formattedWrite("/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)\n");
		sink.formattedWrite("/// Authors: Andrey Penechko\n");
		sink.formattedWrite("/// Auto-generated by vox.fe.lexer.generator\n");
		sink.formattedWrite("module vox.fe.lexer.token_type;\n\n");

		size_t max_term_name = 0;
		foreach(node; terminals) {
			max_term_name = max(max_term_name, node.name.length);
		}
		sink.formattedWrite("enum TokenType : ubyte {\n");
		foreach(node; terminals) {
			auto space = node.comment ? " " : null;
			sink.formattedWrite("\t%s,%s//%s%s\n", node.name, ' '.repeat(max_term_name + 1 - node.name.length), space, node.comment);
		}
		sink.formattedWrite("}\n");
	}
	void writeLexerFile() {
		auto file = File(`tables.d`, "w");
		auto sink = file.lockingBinaryWriter;

		auto len = nonTerminals.length;
		string firstType = "ushort";
		if (len <= 127) {
			firstType = "ubyte";
		}

		// faster by 10% when ordered by byte
		enum orderByByte = true;
		// alignment doesn't matter on big sizes
		size_t nonTermAlignment = 256;
		auto alignedLen = roundUp(len, nonTermAlignment);

		if (!orderByByte) {
			alignedLen = len;
		}

		sink.formattedWrite("/// Copyright: Copyright (c) 2025 Andrey Penechko\n");
		sink.formattedWrite("/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)\n");
		sink.formattedWrite("/// Authors: Andrey Penechko\n");
		sink.formattedWrite("/// Auto-generated by vox.fe.lexer.generator\n");
		sink.formattedWrite("module vox.fe.lexer.tables;\n\n");

		long min_offset = 0;
		// Find negative offset magnitude
		foreach(node; nonTerminals) {
			foreach(uint c; 0..256) {
				if (!node.suffixes[c].isTerminal) {
					auto delta = cast(long)node.suffixes[c].stateIndex - cast(long)node.stateIndex;
					min_offset = min(min_offset, delta);
				}
			}
		}

		// sink.formattedWrite("immutable BY_BYTE = %s;\n", orderByByte);
		sink.formattedWrite("immutable MIN_OFFSET = %s;\n", min_offset);
		sink.formattedWrite("immutable NUM_NONTERMINALS = %s;\n", alignedLen);
		sink.formattedWrite("immutable %s[256] FIRST_STATE = cast(%s[256])x\"", firstType, firstType);
		foreach(uint c; 0..256) {
			if (c % 32 == 0)
				sink.formattedWrite("\n\t");
			sink.formattedWrite(startTerminalFmt(), start.suffixes[c].stateIndex | startTerminalBit(start.suffixes[c]));
		}
		sink.formattedWrite("\";\n");

		auto arrSize = 256 * alignedLen;
		sink.formattedWrite("immutable ubyte[%s] NEXT_STATE = cast(ubyte[%s])x\"", arrSize, arrSize);

		void printItem(uint c, Node* node) {
			if (node.suffixes[c].isTerminal) {
				auto term = node.suffixes[c].stateIndex;
				assert((term & 0b0111_1111) == term,
					format("Terminal is too big %s. %s -> %s", term, node.name, node.suffixes[c].name));
				sink.formattedWrite("%02X", cast(ubyte)(term | 0b1000_0000));
			} else {
				long delta = cast(long)node.suffixes[c].stateIndex - cast(long)node.stateIndex + (-min_offset);
				assert(delta >= 0, "Negative offset");
				assert((delta & 0b0111_1111) == delta, format(
					"Delta is too big %s. %s -> %s", delta, node.name, node.suffixes[c].name));
				sink.formattedWrite("%02X", cast(ubyte)delta);
			}
		}

		if (orderByByte) foreach(uint c; 0..256) {
			sink.formattedWrite("\n\t");
			foreach(node; nonTerminals) {
				printItem(c, node);
			}
			foreach(i; len..alignedLen) {
				sink.formattedWrite("00");
			}
		}
		else foreach(node; nonTerminals) {
			sink.formattedWrite("\n\t");
			foreach(uint c; 0..256) {
				printItem(c, node);
			}
		}
		sink.formattedWrite("\";\n");
	}

	void addId(Identifier id) {
		auto startLength = nonTerminals.length;

		auto idStartNode = start;
		uint prefixSize = 0;
		if (id.sigil != CharClass.init) {
			// Create a sigil node and use it as a start node
			prefixSize = 1;
			auto prefixName = id.keywords[0].token[0..1];
			idStartNode = addNonterminal(new Node(prefixName));
			fill(start, id.sigil, idStartNode);
			fillEmpty(idStartNode, ~id.firstChar, invalid);
		}

		foreach(kw; id.keywords) {
			auto terminal = new Node(kw.enum_name, kw.token, kw.token, isTerminal: true);
			addSuffix(idStartNode, acceptOn: ~id.secondChar, terminal, kw.token.length - prefixSize);
			addTerminal(terminal);
		}

		Node* idTerminal = invalid;
		if (!id.enum_name.empty) idTerminal = new Node(id.enum_name, id.enum_name, id.comment, isTerminal: true);
		Node* id1;

		// Insert extra copies if needed
		// Out of 128 available states we need 0 for self reference, and 2 slots for id1/id2
		// One more for back-references in strings
		enum groupSize = 125;
		auto numNodes = nonTerminals.length - startLength;
		auto nodes = nonTerminals[startLength..$];

		// Remove non-terminals, and readd them with ids
		nonTerminals = nonTerminals[0..startLength];

		// This will store the last id2 node, for start to jump to
		Node* id2;

		foreach(group; 0..divCeil(numNodes, groupSize)) {
			auto from = groupSize * group;
			auto to = min(groupSize * (group+1), numNodes);

			// Make 1 id2 node per group
			id2 = new Node("id2");

			// Process nodes in batches of groupSize (or less)
			// Each group needs to have its own id nodes, so that offset is groupSize max
			foreach(node; nodes[from..to]) {
				fillEmpty(node, id.secondChar, id2);
				fillEmpty(node, ~id.secondChar, idTerminal);
				addNonterminal(node);
			}

			fillEmpty(id2,  id.secondChar, id2);
			fillEmpty(id2, ~id.secondChar, idTerminal);
			addNonterminal(id2);
		}

		fillEmpty(idStartNode, id.firstChar, id2);
		if (idTerminal !is invalid) addTerminal(idTerminal);
	}

	void addOperators(Keyword[] operators) {
		auto startLength = nonTerminals.length;

		foreach(op; operators) {
			auto terminal = new Node(op.enum_name, op.token, op.token, isTerminal: true);
			addSuffix(start, acceptOn: CharClass.all, terminal, op.token.length);
			addTerminal(terminal);
		}

		foreach(node; nonTerminals[startLength..$]) {
			fillEmpty(node, CharClass.all, invalid);
		}
	}

	private void addSuffix(Node* node, CharClass acceptOn, Node* terminal, size_t tail) {
		char head = terminal.token[$-tail];
		auto prefixName = terminal.token[0..$-tail+1];

		auto suffix = node.suffixes[head];
		if (suffix && !suffix.isTerminal) {
			if (tail == 1) {
				fillEmpty(suffix, acceptOn, terminal);
			} else {
				addSuffix(suffix, acceptOn, terminal, tail-1);
			}

			node.suffixes[head] = suffix;
		} else {
			auto suffix2 = addNonterminal(new Node(name: prefixName, prefixName));

			if (tail == 1) {
				fillEmpty(suffix2, acceptOn, terminal);
			} else {
				addSuffix(suffix2, acceptOn, terminal, tail-1);
			}

			node.suffixes[head] = suffix2;
		}
	}

	private void fill(Node* node, CharClass on, Node* target) {
		foreach(char suf; on) {
			node.suffixes[suf] = target;
		}
	}

	private void fillEmpty(Node* node, CharClass on, Node* target) {
		foreach(char suf; on) {
			if (node.suffixes[suf] is null) {
				node.suffixes[suf] = target;
			}
		}
	}
}

ubyte[1] asBytes(ubyte value) {
	return *cast(ubyte[1]*)&value;
}

ubyte[2] asBytes(ushort value) {
	return *cast(ubyte[2]*)&value;
}

ubyte[4] asBytes(uint value) {
	return *cast(ubyte[4]*)&value;
}

struct CharClass {
	ulong[4] bits;

	static CharClass make(string str) {
		CharClass res;
		import core.bitop : bts;
		foreach(char c; str)
			bts(res.bits.ptr, c);
		return res;
	}

	static CharClass all() {
		return CharClass([
			0b1111111111111111111111111111111111111111111111111111111111111111,
			0b1111111111111111111111111111111111111111111111111111111111111111,
			0b1111111111111111111111111111111111111111111111111111111111111111,
			0b1111111111111111111111111111111111111111111111111111111111111111]);
	}

	// _a-zA-Z
	static CharClass id1() {
		return CharClass([
			//?>=<;:9876543210/.-,+*)('&%$#"!
			0b0000000000000000000000000000000000000000000000000000000000000000,
			// ~}|{zyxwvutsrqponmlkjihgfedcba`_^]\[ZYXWVUTSRQPONMLKJIHGFEDCBA@
			0b0000011111111111111111111111111010000111111111111111111111111110,
			0b0000000000000000000000000000000000000000000000000000000000000000,
			0b0000000000000000000000000000000000000000000000000000000000000000]);
	}

	// _a-zA-Z0-9
	static CharClass id2() {
		return CharClass([
			//?>=<;:9876543210/.-,+*)('&%$#"!
			0b0000001111111111000000000000000000000000000000000000000000000000,
			// ~}|{zyxwvutsrqponmlkjihgfedcba`_^]\[ZYXWVUTSRQPONMLKJIHGFEDCBA@
			0b0000011111111111111111111111111010000111111111111111111111111110,
			0b0000000000000000000000000000000000000000000000000000000000000000,
			0b0000000000000000000000000000000000000000000000000000000000000000]);
	}

	// 0-9
	static CharClass digit() {
		return CharClass([
			//?>=<;:9876543210/.-,+*)('&%$#"!
			0b0000001111111111000000000000000000000000000000000000000000000000,
			0b0000000000000000000000000000000000000000000000000000000000000000,
			0b0000000000000000000000000000000000000000000000000000000000000000,
			0b0000000000000000000000000000000000000000000000000000000000000000]);
	}

	// abc1~
	static CharClass test() {
		return CharClass([
			//?>=<;:9876543210/.-,+*)('&%$#"!
			0b0000000000000010000000000000000000000000000000000000000000000000,
			// ~}|{zyxwvutsrqponmlkjihgfedcba`_^]\[ZYXWVUTSRQPONMLKJIHGFEDCBA@
			0b0100000000000000000000000000111000000000000000000000000000000000,
			0b0000000000000000000000000000000000000000000000000000000000000000,
			0b0000000000000000000000000000000000000000000000000000000000000000]);
	}

	static CharClass printable() {
		return CharClass([
			//?>=<;:9876543210/.-,+*)('&%$#"!
			0b1111111111111111111111111111111000000000000000000000000000000000,
			// ~}|{zyxwvutsrqponmlkjihgfedcba`_^]\[ZYXWVUTSRQPONMLKJIHGFEDCBA@
			0b0111111111111111111111111111111111111111111111111111111111111111,
			0b0000000000000000000000000000000000000000000000000000000000000000,
			0b0000000000000000000000000000000000000000000000000000000000000000]);
	}

	CharClass opUnary(string op)()
		if (op == "~")
	{
		ulong[4] res = ~bits[];
		return CharClass(res);
	}

	CharClass opBinary(string op)(CharClass rhs)
		if (op == "|" || op == "^" || op == "&")
	{
		CharClass result;
		foreach(i, cl; bits)
			result.bits[i] = mixin("bits[i] "~op~" rhs.bits[i]");
		return result;
	}

	bool opBinaryRight(string op)(char key) inout if (op == "in") {
		import core.bitop : bt;
		return bt(bits.ptr, key) != 0;
	}

	int opApply(scope int delegate(char) dg) {
		foreach (size_t bitIndex; bitsSet(bits[])) {
			if (int res = dg(cast(char)bitIndex)) return res;
		}
		return 0;
	}
}

BitsSet!T bitsSet(T)(T[] bitmap) { return BitsSet!T(bitmap); }

struct BitsSet(T)
{
	T[] bitmap;

	int opApply(scope int delegate(size_t) dg)
	{
		foreach (size_t slotIndex, T slotBits; bitmap)
		{
			while (slotBits != 0)
			{
				// Extract lowest set isolated bit
				// 111000 -> 001000; 0 -> 0
				T lowestSetBit = slotBits & -slotBits;

				size_t lowestSetBitIndex = bsf(slotBits);
				if (int res = dg(slotIndex * T.sizeof * 8 + lowestSetBitIndex)) return res;

				// Disable lowest set isolated bit
				// 111000 -> 110000
				slotBits ^= lowestSetBit;
			}
		}

		return 0;
	}
}

T divCeil(T)(T a, T b)
{
	return a / b + (a % b > 0);
}

T roundUp(T)(T value, T multiple) pure
{
	assert(multiple != 0, "multiple must not be zero");
	return cast(T)(((value + multiple - 1) / multiple) * multiple);
}
