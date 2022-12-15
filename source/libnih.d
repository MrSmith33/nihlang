/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
import nih.all;

extern(C) export:

struct NihState {
	ubyte dummy;
}

alias AllocCallback = extern(C) void* function(usize size);
alias FreeCallback = extern(C) void function(void* ptr);

NihState* nih_init(AllocCallback alloc) {
	auto state = cast(NihState*)alloc(NihState.sizeof);
	*state = NihState.init;
	return state;
}

void nih_free(NihState* state, FreeCallback free) {
	free(state);
}
