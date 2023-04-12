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
