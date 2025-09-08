/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.fe.lexer;

import vox.lib;
import vox.fe.lexer.token;
import vox.fe.lexer.token_type;
import vox.fe.lexer.tables;

struct Lexer
{
	@nogc nothrow:

	const(char)[] input;
	uint position;
	uint line;
	uint column;

	Token nextToken() {
		uint curPosition = position;
		uint curLine = line;
		uint curColumn = column;
		// skip whitespace
		while(true)
		{
			char ch = input[curPosition];
			if (ch == ' ' || ch == '\t' || ch == '\r') {
				++curColumn;
			} else if (ch == '\n') {
				curColumn = 0;
				++curLine;
			} else {
				break;
			}
			++curPosition;
		}

		// store token position
		uint startPos = curPosition;
		uint startLine = curLine;
		uint startCol = curColumn;

		// First loop iteration, that takes absolute position from FIRST_STATE
		ubyte firstCh = input[curPosition];
		uint state = FIRST_STATE[firstCh];
		if (state & 0b1000_0000_0000_0000) goto after_loop;

		if (firstCh == '\n') {
			curColumn = 0;
			++curLine;
		} else {
			++curColumn;
		}
		++curPosition;

		while(true)
		{
			char ch = input[curPosition];
			auto nextState = NEXT_STATE[ch * NUM_NONTERMINALS + state];

			if (nextState & 0b1000_0000) {
				// this is a terminal state
				state = nextState;
				break;
			}

			state += nextState + MIN_OFFSET;

			if (ch == '\n') {
				curColumn = 0;
				++curLine;
			} else {
				++curColumn;
			}
			++curPosition;
		}
		after_loop:

		position = curPosition;
		line = curLine;
		column = curColumn;

		return Token(startPos, curPosition, startLine, startCol, cast(TokenType)(state & 0b0111_1111));
	}
}
