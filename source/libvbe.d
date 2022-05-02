/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
import vox.all;

extern(C) export:

struct VbeState {
	ubyte dummy;
}

alias AllocCallback = extern(C) void* function(size_t size);
alias FreeCallback = extern(C) void function(void* ptr);

VbeState* vbe_init(AllocCallback alloc) {
	auto state = cast(VbeState*)alloc(VbeState.sizeof);
	*state = VbeState.init;
	return state;
}

void vbe_free(VbeState* state, FreeCallback free) {
	free(state);
}
