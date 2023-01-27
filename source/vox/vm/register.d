/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.register;

import vox.lib;
import vox.vm.memory;

@nogc nothrow:


// Register can contain 0 or 1 pointer, so instead of storing a hashmap of relocations
// we store a single AllocationId
// vector registers are forbidden to store pointers
align(16)
struct VmRegister {
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
	AllocationId pointer;

	void toString(scope SinkDelegate sink, FormatSpec spec) @nogc nothrow const {
		if (pointer.isDefined) {
			sink.formattedWrite("%s%s", memoryKindLetter[pointer.kind], pointer.index);
			if (as_u64 != 0) {
				sink.formattedWrite("+%s", as_u64);
			}
		} else {
			sink.formatValue(as_u64);
		}
	}

	static VmRegister makePtr(u64 offset, AllocationId alloc) {
		VmRegister r = {
			as_u64 : offset,
			pointer : alloc,
		};
		return r;
	}
}

VmRegister vmRegPtr(AllocationId allocId) {
	return VmRegister.makePtr(0, allocId);
}
