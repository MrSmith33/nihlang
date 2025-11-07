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
	CoffExecutable exe;
	Array!u8 exeBytes;
	exe.write(*c.allocator, exeBytes);
	exe.parse(exeBytes[]);
	//formattedWrite(c.sink, "%s", exe);
}
