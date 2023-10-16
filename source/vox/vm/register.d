/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.register;

import vox.lib;
import vox.vm.memory;

@nogc nothrow:


// Register can contain 0 or 1 pointer, so instead of storing a hashmap of outRefs
// we store a single AllocId
// vector registers are forbidden to store pointers
//
// 1) What if we read uninitialized register?
align(16)
struct VmReg {
	@nogc nothrow:
	union {
		u64 as_u64; // init union to 0
		u8  as_u8;
		u16 as_u16;
		u32 as_u32;
		i8  as_s8;
		i16 as_s16;
		i32 as_s32;
		i64 as_s64;
		f32 as_f32;
		f64 as_f64;
	}
	AllocId pointer;

	ref T get(T)() if(is(T == u8))  { return as_u8; }
	ref T get(T)() if(is(T == u16)) { return as_u16; }
	ref T get(T)() if(is(T == u32)) { return as_u32; }
	ref T get(T)() if(is(T == u64)) { return as_u64; }
	ref T get(T)() if(is(T == i8))  { return as_s8; }
	ref T get(T)() if(is(T == i16)) { return as_s16; }
	ref T get(T)() if(is(T == i32)) { return as_s32; }
	ref T get(T)() if(is(T == i64)) { return as_s64; }
	ref  u8 get_u(T)() if(is(T == u8)  || is(T ==  i8)) { return as_u8; }
	ref u16 get_u(T)() if(is(T == u16) || is(T == i16)) { return as_u16; }
	ref u32 get_u(T)() if(is(T == u32) || is(T == i32)) { return as_u32; }
	ref u64 get_u(T)() if(is(T == u64) || is(T == i64)) { return as_u64; }
	ref  i8 get_s(T)() if(is(T == u8)  || is(T ==  i8)) { return as_s8; }
	ref i16 get_s(T)() if(is(T == u16) || is(T == i16)) { return as_s16; }
	ref i32 get_s(T)() if(is(T == u32) || is(T == i32)) { return as_s32; }
	ref i64 get_s(T)() if(is(T == u64) || is(T == i64)) { return as_s64; }

	bool opEquals(VmReg other) {
		pragma(inline, true);
		return as_u64 == other.as_u64 && pointer == other.pointer;
	}

	void toString(scope SinkDelegate sink, FormatSpec spec) @nogc nothrow const {
		if (pointer.isDefined) {
			sink.formattedWrite("%s%s", memoryKindLetter[pointer.kind], pointer.index);
			if (as_u64 != 0) {
				if (as_s64 > 0)
					sink.formattedWrite("+%s", as_s64);
				else
					sink.formattedWrite("%s", as_s64);
			}
		} else {
			sink.formatValue(as_u64);
		}
	}

	this(u64 num) {
		this.as_u64 = num;
	}

	this(f32 num) {
		this.as_f32 = num;
	}

	this(f64 num) {
		this.as_f64 = num;
	}

	this(AllocId ptr, u64 offset = 0) {
		this.as_u64 = offset;
		this.pointer = ptr;
	}
}
