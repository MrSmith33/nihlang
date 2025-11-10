/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.formats.pecoff.tests;

import vox.lib;
import vox.tests.infra;
import vox.fe.lexer;
import vox.fe.lexer.token_type;

import vox.lib.formats.pecoff.executable;

@Test
void test_pecoff_write_parse(ref SimpleTestContext c) {
	CoffExecutable exe1;
	Array!u8 exe1Bytes;
	exe1.write(*c.allocator, exe1Bytes);

	CoffExecutable exe2;
	exe2.parse(exe1Bytes[]);

	// Check that writing and parsing pecoff executable yields the same data
	assert(exe1 == exe2, "write/parse pair have diverged");
	//formattedWrite(c.sink, "%s", exe1);
	//formattedWrite(c.sink, "%s", exe2);
}
