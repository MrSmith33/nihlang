/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.error;

@nogc nothrow:

noreturn panic(Args...)(string fmt, Args args, string file = __FILE__, int line = __LINE__) {
	panic(line, file, 0, fmt, args);
}
noreturn panic(Args...)(int line, string file, int topFramesToSkip, string fmt, Args args) {
	import vox.lib.io : writefln, writef, writeln;
	import vox.lib.system.entrypoint : vox_exit_process;
	//writefln("\033[1;31mPanic:\033[0m %s:%s", file, line);
	writefln("Panic at %s:%s", file, line);
	writef(fmt, args);
	writeln;
	version(Windows) {
		writeln("Stack trace:");
		import vox.lib.stacktrace : simpleNamedStackTrace;
		simpleNamedStackTrace(3,2+topFramesToSkip);
	}
	vox_exit_process(1);
}

T enforce(T, Args...)(T value, string fmt, Args args, string file = __FILE__, int line = __LINE__)
	if (is(typeof(() { if (!value) { } } )))
{
	import vox.lib.io : writefln, writef, writeln;
	import vox.lib.system.entrypoint : vox_exit_process;
	if (value) return value;

	writefln("Enforce: %s:%s", file, line);
	writef(fmt, args);
	writeln;
	version(Windows) {
		import vox.lib.stacktrace : simpleNamedStackTrace;
		simpleNamedStackTrace(3,2);
	}
	vox_exit_process(1);
}

version(D_BetterC) {
	version(WebAssembly) extern(C) void __assert(const(char)* msg, const(char)* file, uint line) {
		_assert(msg, file, line);
	}
	extern(C) void _assert(const(char)* msg, const(char)* file, uint line) {
		import vox.lib.io : writefln, writef, writeln;
		import vox.lib.system.entrypoint : vox_exit_process;
		import vox.lib.string : fromStringz;
		writef("%s:%s Assert: ", file.fromStringz, line);
		msg.fromStringz.writeln;
		version(Windows) {
			import vox.lib.stacktrace : simpleNamedStackTrace;
			simpleNamedStackTrace(3,2);
		}
		vox_exit_process(1);
	}
}
