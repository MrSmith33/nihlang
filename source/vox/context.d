/// Copyright: Copyright (c) 2026 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
module vox.context;

import vox.lib;
import vox.source;

// 0 One global context for all compilations
//   Hosts all worker and all builds
// 1 One context per compilation/build
// 2 One context per worker thread
//
// Job system is created together with global context.
// New builds can be added/cancelled at any time.
// When build finishes we want to free its memory, or leave it in memory for execution/inspection
// When memory is freed it should be freed from all thread contexts in case we store data there.
// If we reuse a container for all builds, like a hashmap of interned strings, we might want to leave it as is.

//
struct Driver {
	@nogc nothrow:
	VoxContext context;

	Result!void init(ref Allocator allocator) {
		enum _64KiB = 65_536;
		enum _1MiB = 1024*1024;

		auto sourceMem = allocator.allocBlock(_1MiB);
		if (sourceMem.isError) return Result!void.makeError(1);
		context.bufs.sources.setBuffer(sourceMem.data);

		auto filesMem = allocator.allocBlock(_64KiB);
		if (filesMem.isError) return Result!void.makeError(1);
		context.bufs.files.setBuffer(filesMem.data);

		auto stringsMem = allocator.allocBlock(_64KiB);
		if (stringsMem.isError) return Result!void.makeError(1);
		context.bufs.strings.setBuffer(stringsMem.data);

		auto errorsMem = allocator.allocBlock(_64KiB);
		if (errorsMem.isError) return Result!void.makeError(1);
		context.bufs.errors.setBuffer(errorsMem.data);

		return Result!void();
	}

	void startCompilation() {
		context.bufs.clear();
	}

	void addHar(string harFilename, const(char)[] harData) {
		import vox.lib.har;
		void onFile(const(char)[] name, const(char)[] data) {
			auto offset = context.bufs.sources.length;
			char[] sourceBuf = context.bufs.sources.voidPut(data.length);
			sourceBuf[] = data;
			// Pad so we can use faster utf-8 decoder, that reads 4 bytes at a time
			context.bufs.sources.put(cast(char[])"\0\0\0");
			FileInfo info = {
				name : name,
				offset : cast(u32)offset,
				length : cast(u32)data.length,
			};
			context.bufs.files.put(info);
		}
		void onError(size_t start, size_t end, string msg) {
			writefln("HAR error: (%s, %s) %s", start, end, msg);
			assert(false);
		}
		parseHar(harData, &onError, &onFile);
	}

	void compile() {
		foreach(ref file; context.bufs.files.data) {
			import vox.fe.lexer;
			import vox.fe.lexer.token_type;
			import vox.fe.parser;

			Parser parser = Parser(&context);
			parser.parseModule(file);
		}
	}
}

struct Buffers {
	@nogc nothrow:

	Arena!char sources;
	Arena!FileInfo files;
	ArrayArena arrayArena;
	NameMap nameMap;
	Arena!char strings;
	Arena!u8 errors;

	void clear() {
		sources.clear;
		files.clear;
		arrayArena.clear;
		//nameMap
		strings.clear;
		errors.clear;

		// 0 position is reserved for null position
		sources.put(0);
	}
}

struct Diagnostic {
	string msg;
	Annotation[] annotations;
	// TODO: stack trace
}

struct Annotation {
	string msg; // optional
	Span location;
}

// multiple BuildContext and ThreadContext
struct VoxContext {
	@nogc nothrow:
	Buffers bufs;

	Result!T makeError(T, Args...)(Span span, string fmt, Args args) {
		auto startLen = bufs.strings.length;
		formattedWrite(&putString, fmt, args);
		auto endLen = bufs.strings.length;
		//writeln(cast(string)bufs.strings[startLen..endLen]);
		return Result!T.makeError(1); // TODO: return index of error object
	}

	void putString(scope const(char)[] str) {
		bufs.strings.put(str);
	}
}

// Single build/compilation, single VoxContext
struct BuildContext {

}

// Single thread, single VoxContext, multiple BuildContext
struct ThreadContext {

}
