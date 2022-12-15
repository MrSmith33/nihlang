/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.utils.entrypoint;

import vox.all;

@nogc nothrow:

version(EXECUTABLE) {
	pragma(mangle, "vox_main") i32 vox_main(string[] args);

	version(NO_DEPS) {
		version(Windows) export extern(System)
		noreturn exe_main(void* hInstance, void* hPrevInstance,
		                  char* lpCmdLine, i32 nCmdShow)
		{
			initDbgHelp;
			i32 ret = vox_main(null);
			vox_exit_process(ret);
		}

		version(Posix) export extern(C)
		noreturn exe_main() {
			i32 ret = vox_main(null);
			vox_exit_process(ret);
		}

		version(OSX) export extern(C)
		noreturn main() {
			i32 ret = vox_main(null);
			vox_exit_process(ret);
		}

		version(WebAssembly) export extern(C)
		void _start() {
			vox_main(null);
		}
	}

	version(VANILLA_D)
	i32 main(string[] args) {
		return vox_main(args);
	}
}

version(SHARED_LIB) {
	version(Windows) extern(System) bool DllMain(void* instance, u32 reason, void* reserved) {
		return true;
	}
}
