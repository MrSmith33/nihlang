/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.io;

import vox.lib;

@nogc nothrow:


enum u32 stdin  = 0;
enum u32 stdout = 1;
enum u32 stderr = 2;

void writefln(Args...)(string fmt, Args args) {
	void sink(scope const(char)[] str) @nogc nothrow {
		writeString(str);
	}
	formattedWrite(&sink, fmt, args);
	writeString("\n");
}

void writef(Args...)(string fmt, Args args) {
	void sink(scope const(char)[] str) @nogc nothrow {
		writeString(str);
	}
	formattedWrite(&sink, fmt, args);
}

void writeln(Args...)(Args args) {
	void sink(scope const(char)[] str) @nogc nothrow {
		writeString(str);
	}
	foreach(i, arg; args) {
		selectFormatter!(Args[i])(&sink, arg, "s");
	}
	writeString("\n");
}

void write(Args...)(Args args) {
	void sink(scope const(char)[] str) {
		writeString(str);
	}
	foreach(i, arg; args) {
		selectFormatter!(Args[i])(&sink, arg, "s");
	}
}


void testWrite() @nogc nothrow {
	char[512] buf = void;
	u32 cursor;
	void testSink(scope const(char)[] str) @nogc nothrow {
		buf[cursor..cursor+str.length] = str;
		cursor += str.length;
	}
	void test(Args...)(string expected, string fmt, Args args, string file = __FILE__, int line = __LINE__) {
		cursor = 0;
		formattedWrite(&testSink, fmt, args);
		if (expected != buf[0..cursor]) {
			writefln("\033[1;31m[FAIL]\033[0m %s:%s", file, line);
			writefln("Got:      %s", buf[0 .. cursor]);
			writefln("Expected: %s", expected);
			panic("panic");
		}
	}

	scope(exit) writeln("\033[1;32m[SUCCESS]\033[0m");

	test("c", "%s", 'c');
	test("\xFF", "%s", '\xFF');
	test("\U0000FFFF", "%s", '\U0000FFFF');

	test("hello", "%s", "hello");
	test("18446744073709551615", "%s", u64(-1));
	test("0", "%s", u64(0));
	test("18446744073709551615", "%s", u64(0xFFFF_FFFF_FFFF_FFFF));

	test("-9223372036854775808", "%s", i64(-9223372036854775808));
	test("-1", "%s", i64(-1));
	test("0", "%s", i64(0));
	test("9223372036854775807", "%s", i64(9223372036854775807));

	test("ffffffffffffffff", "%x", u64(0xFFFF_FFFF_FFFF_FFFF));
	test("FFFFFFFFFFFFFFFF", "%X", u64(0xFFFF_FFFF_FFFF_FFFF));

	test("4.5", "%s", 4.5);
	test("1.200000", "%s", 1.2f);

	int* b = cast(int*)0x0F0F_F0FF_F0FF_FFF0;
	test("0xF0FF0FFF0FFFFF0", "%s", b);

	test("true", "%s", true);
	test("false", "%s", false);
	test("null", "%s", null);

	static int[] arr = [1, 2];
	test("[1, 2]", "%s", arr);

	static int[2] arr2 = [1, 2];
	test("[1, 2]", "%s", arr2);

	static struct A {
		i32 a = 42;
		i32 b = 60;
	}

	static struct B	{
		void toString(scope SinkDelegate sink) @nogc nothrow const {
			sink("it's B");
		}
	}
	test("A(a : 42, b : 60)", "%s", A());
	test("it's B", "%s", B());
}
