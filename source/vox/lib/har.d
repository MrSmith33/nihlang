/// Copyright: Copyright (c) 2026 Andrey Penechko.
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
/// Authors: Andrey Penechko.

/// Parses HAR - Human Archive Format: https://github.com/marler8997/har
module vox.lib.har;

@nogc nothrow:

void parseHar(
	const(char)[] harData,
	scope void delegate(size_t start, size_t end, string msg) @nogc nothrow onError,
	scope void delegate(const(char)[] name, const(char)[] data) @nogc nothrow onFile)
{
	if (harData.length == 0) return;

	auto data = harData;
	auto line = popLine(data);
	size_t spaceIndex = 0;
	foreach(i, char c; line) {
		if (c == ' ') {
			spaceIndex = i;
			break;
		}
	}
	if (spaceIndex == 0) {
		return onError(0, line.length, "First line must start with delimiter ending with space");
	}

	// +1 to include space into delimiter
	auto delimiter = line[0 .. spaceIndex + 1];
    //writefln("delimiter '%s'", delimiter);

	while (true) {
		auto filename = line[delimiter.length .. $];
        //writefln("line %s", filename.length);
		if (filename.length == 0) {
			auto start = filename.ptr - harData.ptr;
			return onError(start, start + 1, "Missing filename after delimiter");
		}

		const(char)* fileStart = data.ptr;

		// Get all lines of a file
		while (true) {
			const(char)* fileEnd = data.ptr;

			if (data.length == 0) {
				onFile(filename, fileStart[0..fileEnd-fileStart]);
				return;
			}

			line = popLine(data);
            //writefln("line '%s'", line);

            import vox.lib.algo : startsWith;
			if (line.startsWith(delimiter)) {
				onFile(filename, fileStart[0..fileEnd-fileStart]);
				break;
			}
		}
	}
}

const(char)[] peekLine(const(char)[] data) {
	import vox.lib.string : lineSize;
    auto size = lineSize(data);
    auto line = data[0..size.lineLength - size.terminatorLength];
    return line;
}

const(char)[] popLine(ref const(char)[] data) {
	import vox.lib.string : lineSize;
    auto size = lineSize(data);
    auto line = data[0..size.lineLength - size.terminatorLength];
    data = data[size.lineLength..$];
    return line;
}

unittest {
	@nogc nothrow:
    struct File { string name, data; }
    void test(string data, File[] files) {
        size_t fileIndex;
        @nogc nothrow:
        void onFile(const(char)[] name, const(char)[] data) {
            if (fileIndex >= files.length) {
            	writefln("Too many files in a test. Expected %s files, got at least %s files", files.length, fileIndex+1);
                assert(false);
            }
            if (name != files[fileIndex].name) goto no_match;
            if (data != files[fileIndex].data) goto no_match;
            //writefln("--- %s\n%s", name, data);
            ++fileIndex;
            return;

        no_match:
            writefln("Incorrect file:");
            writefln("Expected:\n  name='%s'\n  data='%s'", files[fileIndex].name, files[fileIndex].data);
            writefln("Got:\n  name='%s'\n  data='%s'", name, data);
            assert(false);
        }
        void onError(size_t start, size_t end, string msg) {
            writefln("Unexpected error in a test: (%s, %s) %s", start, end, msg);
            assert(false);
        }
        parseHar(data, &onError, &onFile);
    }
    void testErr(string data, size_t exp_start, size_t exp_end, string exp_msg) {
        void onFile(const(char)[] filename, const(char)[] filedata) {}
        bool gotError;
        @nogc nothrow:
        void onError(size_t start, size_t end, string msg) {
            if (exp_start != start) goto no_match;
            if (exp_end != end) goto no_match;
            if (exp_msg != msg) goto no_match;
            gotError = true;
            return;

        no_match:
            writefln("Incorrect error:");
            writefln("Expected: (%s, %s) %s", exp_start, exp_end, exp_msg);
            writefln("     Got: (%s, %s) %s", start, end, msg);
            assert(false);
        }
        parseHar(data, &onError, &onFile);
        if (!gotError) {
        	writefln("Test succeeded, while expected error: (%s, %s) %s", exp_start, exp_end, exp_msg);
            assert(false);
        }
    }

    test("", []);
    test("--- test", [File("test")]);
    test("--- test\ndata", [File("test", "data")]);
    test("--- test\ndata\n", [File("test", "data\n")]);
    test("--- test\ndata\n--- test2\ndata2", [File("test", "data\n"), File("test2", "data2")]);
    test("--- test\ndata\n--- test2\ndata2\n", [File("test", "data\n"), File("test2", "data2\n")]);
    testErr("---", 0, 3, "First line must start with delimiter ending with space");
    testErr("---\n", 0, 3, "First line must start with delimiter ending with space");
    testErr("--- ", 4, 5, "Missing filename after delimiter");
    testErr("--- \n", 4, 5, "Missing filename after delimiter");
}
