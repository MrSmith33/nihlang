/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

// Implementation of memset, memcpy, memmove, and memcmp for x64
// Copy of https://github.com/skeeto/w64devkit/blob/master/src/libmemory.c
module vox.lib.sys.arch.x64.memory;

extern(C) @nogc nothrow @system:
