/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.io;

import vox.lib;

@nogc nothrow:


enum u32 stdin  = 0;
enum u32 stdout = 1;
enum u32 stderr = 2;

immutable SinkDelegate stdoutSink = delegate void(scope const(char)[] str) @nogc nothrow {
	writeString(str);
};

void writefln(Args...)(string fmt, Args args) {
	formattedWrite(stdoutSink, fmt, args);
	writeString("\n");
}

void writef(Args...)(string fmt, Args args) {
	formattedWrite(stdoutSink, fmt, args);
}

void writeln(Args...)(Args args) {
	foreach(i, arg; args) {
		selectFormatter!(Args[i])(stdoutSink, arg, FormatSpec());
	}
	writeString("\n");
}

void write(Args...)(Args args) {
	foreach(i, arg; args) {
		selectFormatter!(Args[i])(stdoutSink, arg, FormatSpec());
	}
}
