/// Copyright: Copyright (c) 2025 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
module vox.tests.context;

import vox.lib;
import vox.tests.infra;
import vox.source;

struct VoxTestContext {
	mixin TestContextUtils;

	@nogc nothrow:

	Allocator* allocator;
	SinkDelegate sink;
	TestInstance test;
	Driver driver;

	this(Allocator* allocator, SinkDelegate _sink) {
		this.allocator = allocator;
		sink = _sink;
	}

	void init() {
		assert(!driver.init(*allocator).isError);
	}

	void runTest(ref TestInstance _test) {
		test = _test;
		driver.startCompilation();
		test.test_handler(&this);
	}

	T* getGlobalPtr(T)(string name) {
		assert(false, "TODO");
		return null;
	}
}

struct FileInfo {
	const(char)[] name;
	// Offset into bufs.file
	u32 offset;
	// Doesn't include zero bytes at the end
	u32 length;
}

struct Buffers {
	@nogc nothrow:

	import vox.lib.mem.arena : Arena;
	Arena!char sources;
	Arena!FileInfo files;

	void clear() {
		sources.clear;
		files.clear;
	}
}

struct Driver {
	@nogc nothrow:
	Buffers bufs;

	Result!void init(ref Allocator allocator) {
		enum _64KiB = 65_536;
		enum _1MiB = 1024*1024;

		auto sourceMem = allocator.allocBlock(_1MiB);
		if (sourceMem.isError) return Result!void.makeError(1);
		bufs.sources.setBuffer(sourceMem.data);

		auto filesMem = allocator.allocBlock(_64KiB);
		if (filesMem.isError) return Result!void.makeError(1);
		bufs.files.setBuffer(filesMem.data);

		return Result!void();
	}

	void startCompilation() {
		bufs.clear();
	}

	void addHar(string harFilename, const(char)[] harData) {
		import vox.lib.har;
		void onFile(const(char)[] name, const(char)[] data) {
			auto offset = bufs.sources.length;
			char[] sourceBuf = bufs.sources.voidPut(data.length);
			sourceBuf[] = data;
			// Pad so we can use faster utf-8 decoder, that reads 4 bytes at a time
			bufs.sources.put(cast(char[])"\0\0\0");
			FileInfo info = {
				name : name,
				offset : cast(u32)offset,
				length : cast(u32)data.length,
			};
			bufs.files.put(info);
		}
		void onError(size_t start, size_t end, string msg) {
			writefln("HAR error: (%s, %s) %s", start, end, msg);
			assert(false);
		}
		parseHar(harData, &onError, &onFile);
	}

	void compile() {
		foreach(ref file; bufs.files.data) {
			import vox.fe.lexer;
			import vox.fe.lexer.token_type;
			auto source = bufs.sources.data[file.offset..file.offset + file.length+3];
			auto lexer = Lexer(source.ptr);
			//writefln("--- %s at %s\n%s", file.name, file.offset, source);
			while(true) {
				auto tok = lexer.nextToken;
				//writefln("  %s", cast(uint)tok.tok);
				if (tok.type == TokenType.eoi) break;
			}
		}
	}
}
