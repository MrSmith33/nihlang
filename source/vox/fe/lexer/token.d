/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.fe.lexer.token;

import vox.lib.format;
import vox.fe.lexer.token_type;

struct Token {
	@nogc nothrow:

	uint start;
	uint end;
	uint line;
	uint col;
	TokenType tok;

	const(char)[] getTokenString(const(char)[] input) pure const {
		return input[start..end];
	}

	void toString(scope SinkDelegate sink) const {
		sink.formattedWrite("line %s col %s start %s end %s len %s %s", line+1, col+1, start, end, end-start, tok);
	}
}
