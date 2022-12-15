/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module main;

@nogc nothrow:

import nih.all;

pragma(mangle, "vox_main")
i32 vox_main(string[] args)
{
	writeln("NIH compiler CLI v0.0.0");
	return 0;
}
