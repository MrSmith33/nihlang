/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.utils.error;

import vox.utils;

@nogc nothrow:

noreturn panic(Args...)(string fmt, Args args, string file = __FILE__, int line = __LINE__) {
	//writefln("\033[1;31mPanic:\033[0m %s:%s", file, line);
	writefln("Panic: %s:%s", file, line);
	writef(fmt, args);
	writeString("\n");
	//simpleStackTrace(2);
	version(Windows) simpleNamedStackTrace(3,2);
	vox_exit_process(1);
}

version(D_BetterC) {
	extern(C) void _assert(const(char)* msg, const(char)* file, uint line) {
		writef("%s:%s Assert: ", file.fromStringz, line);
		msg.fromStringz.writeln;
		version(Windows) simpleNamedStackTrace(3,2);
		vox_exit_process(1);
	}
}
