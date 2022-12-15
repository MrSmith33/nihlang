/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.utils.types;

version(D_BetterC) {
	alias noreturn = typeof(*null);
	alias string = immutable(char)[];
}

alias u8 = ubyte;
alias u16 = ushort;
alias u32 = uint;
alias u64 = ulong;
alias usize = typeof(int.sizeof);
alias i8 = byte;
alias i16 = short;
alias i32 = int;
alias i64 = long;
alias isize = typeof(cast(void*)0 - cast(void*)0);
alias f32 = float;
alias f64 = double;
