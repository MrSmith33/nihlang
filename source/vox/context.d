/// Copyright: Copyright (c) 2026 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
module vox.context;

import vox.lib;
import vox.fe.source;

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
		if (sourceMem.isError) return Result!void.fromError(sourceMem);
		context.bufs.sources.setBuffer(sourceMem.data);

		auto filesMem = allocator.allocBlock(_64KiB);
		if (filesMem.isError) return Result!void.fromError(filesMem);
		context.bufs.files.setBuffer(filesMem.data);

		auto arrayMem = allocator.allocBlock(_1MiB);
		if (arrayMem.isError) return Result!void.fromError(arrayMem);
		auto bigArrayMem = allocator.allocBlock(_1MiB);
		if (bigArrayMem.isError) return Result!void.fromError(bigArrayMem);
		context.bufs.arrayArena.setBuffers(arrayMem.data, bigArrayMem.data);

		auto nameStr = allocator.allocBlock(_64KiB);
		if (nameStr.isError) return Result!void.fromError(nameStr);
		auto nameEntries = allocator.allocBlock(_64KiB);
		if (nameEntries.isError) return Result!void.fromError(nameEntries);
		context.bufs.nameMap.stringDataBuffer.setBuffer(nameStr.data);
		context.bufs.nameMap.entries.setBuffer(nameEntries.data);

		auto stringsMem = allocator.allocBlock(_64KiB);
		if (stringsMem.isError) return Result!void.fromError(stringsMem);
		context.bufs.strings.setBuffer(stringsMem.data);

		auto errorsMem = allocator.allocBlock(_64KiB);
		if (errorsMem.isError) return Result!void.fromError(errorsMem);
		context.bufs.errors.setBuffer(errorsMem.data);

		auto astMem = allocator.allocBlock(_64KiB);
		if (astMem.isError) return Result!void.fromError(astMem);
		context.bufs.ast.setBuffer(astMem.data);

		auto initRes = context.initialize();
		if (initRes.isError) return Result!void.fromError(initRes);

		return Result!void();
	}

	Result!void startCompilation() {
		return context.bufs.startCompilation();
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

	Result!void compile() {
		foreach(ref file; context.bufs.files.data) {
			import vox.fe.lexer;
			import vox.fe.lexer.token_type;
			import vox.fe.parser;

			Parser parser = Parser(&context);
			auto res = parser.parseModule(file);
			if (res.isError) return res;
		}
		return Result!void();
	}
}

struct Buffers {
	@nogc nothrow:

	Arena!char sources;
	Arena!FileInfo files;
	ArrayArena arrayArena;
	NameMap nameMap;
	Arena!char strings;
	Arena!u32 errors;
	Arena!u32 ast;

	// Stores ast.length after initialize() call
	// to be reset on startCompilation()
	usz initializedAstBufSize;

	// Runs for each compilation
	// TODO: Incompatible with multiple compilations at once
	Result!void startCompilation() {
		sources.clear;
		files.clear;

		arrayArena.clear;
		strings.clear;
		errors.clear;
		ast.length = initializedAstBufSize;

		nameMap.stringDataBuffer.clear;
		nameMap.entries.clear;
		nameMap.map = typeof(nameMap.map).init;
		nameMap.fqnMap = typeof(nameMap.fqnMap).init;

		auto res = nameMap.regCommonNames(arrayArena);
		if (res.isError) return Result!void.fromError(res);

		// 0 position is reserved for null position
		sources.put(0);
		// 0 position is reserved for no error
		errors.put(0);

		return Result!void();
	}
}

struct Diagnostic {
	string msg;
	Array!Annotation annotations;
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

	// Runs ones when context is created
	Result!void initialize() {
		// populates nameMap with common identifiers like this, length, ptr, min, max, sizeof...
		auto res = bufs.nameMap.regCommonNames(bufs.arrayArena);
		if (res.isError) return Result!void.fromError(res);

		// 0 position is reserved for null position
		bufs.ast.put(0);

		auto t_i32 = appendAst!BasicType(BasicTypeEnum.t_i32);
		assert(t_i32 == 1);

		bufs.initializedAstBufSize = bufs.ast.length;

		return Result!void();
	}

	string getString(Name name) {
		return bufs.nameMap.get(name);
	}

	string getString(Span span) {
		return span.getString(bufs.sources.data);
	}

	Span getTokenSpan(Position start) {
		import vox.fe.lexer : Lexer;
		Lexer lexer;
		lexer.input = bufs.sources.bufPtr;
		lexer.position = start.offset;
		lexer.line = 0;
		lexer.column = 0;
		return lexer.nextToken().location;
	}

	Result!T makeError(T, Args...)(Span loc, string fmt, Args args) {
		auto startLen = bufs.strings.length;
		formattedWrite(&putStr, fmt, args);
		auto endLen = bufs.strings.length;
		auto msg = cast(string)bufs.strings[startLen..endLen];
		Array!Annotation annotations;
		auto res = annotations.put(bufs.arrayArena, Annotation("here", loc));
		if (res.isError) return Result!T.fromError(res);

		auto index = appendError!Diagnostic(msg, annotations);
		return Result!T.fromError(index);
	}

	u32 appendError(T, Args...)(Args args) {
		uint resIndex = bufs.errors.uintLength;
		T* obj = cast(T*)bufs.errors.nextPtr;
		enum size_t numAllocatedSlots = divCeil(T.sizeof, uint.sizeof);
		bufs.errors.voidPut(numAllocatedSlots);
		*obj = T(args);
		return resIndex;
	}

	ref T getError(T)(u32 index) {
		return *cast(T*)(&bufs.errors.bufPtr[index]);
	}

	AstIndex appendAst(T, Args...)(Args args) {
		uint resIndex = bufs.ast.uintLength;
		T* obj = cast(T*)bufs.ast.nextPtr;
		enum size_t numAllocatedSlots = divCeil(T.sizeof, uint.sizeof);
		bufs.ast.voidPut(numAllocatedSlots);
		*obj = T(args);
		return AstIndex(resIndex);
	}

	T* getAst(T)(AstIndex index) {
		if (!index) return null;
		T* result = cast(T*)(&bufs.ast.bufPtr[index.storageIndex * uint.sizeof]);
		return result;
	}

	// WASM doesn't like when we cast cast(SinkDelegate)&bufs.strings.put
	// wasm trap: indirect call type mismatch
	void putStr(scope const(char)[] str) {
		bufs.strings.put(str);
	}
}

enum CommonAstNodes : AstIndex {
	// reserved for undefined
	undefined                = AstIndex(0),

	type_i32                 = AstIndex(1),
}

struct AstNode {
	uint data;
}

alias AstIndex = u32;

alias AstNodes = Array!AstIndex;

struct ModuleDecl {
	AstNodes declarations;
}

struct BasicType {
	BasicTypeEnum kind;
	enum NumStorageSlots = divCeil(BasicType.sizeof, u32.sizeof);
}


enum BasicTypeEnum : u8 {
	t_error,
	t_auto,
	t_noreturn,
	t_void,
	t_bool,
	t_null,

	t_i8,
	t_i16,
	t_i32,
	t_i64,

	t_u8,
	t_u16,
	t_u32,
	t_u64,

	t_f32,
	t_f64,

	// meta types
	t_alias,
	t_type,
}

struct NameUse {
	NameWithPos identifier;
	AstIndex target;
}

struct VariableDecl {
	NameWithPos identifier;
}

// Single build/compilation, single VoxContext
struct BuildContext {

}

// Single thread, single VoxContext, multiple BuildContext
struct ThreadContext {

}
