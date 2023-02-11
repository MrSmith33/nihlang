/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module testone;

@nogc nothrow:

import nih.all;
import vox.vm.tests.infra.runner;

pragma(mangle, "vox_main")
i32 vox_main(string[] args)
{
	runVmTests();
	return 0;
}
