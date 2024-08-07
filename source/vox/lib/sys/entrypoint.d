/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
/// Entry points for executable and shared library targets
module vox.lib.sys.entrypoint;

import vox.all;

@nogc nothrow:

version(EXECUTABLE) {
	pragma(mangle, "vox_main") i32 vox_main(string[] args);

	version(NO_DEPS) {
		version(Windows) extern(System)
		noreturn exe_main(void* hInstance, void* hPrevInstance,
						  char* lpCmdLine, i32 nCmdShow)
		{
			initDbgHelp;
			vox_init();
			i32 ret = vox_main(null);
			vox_exit_process(ret);
		}

		version(Posix) {
			export extern(C)
			noreturn exe_main() {
				version(X86_64) {
					asm @nogc nothrow {
						sub RSP, 8;
					}
				}
				vox_init();
				i32 ret = vox_main(null);
				vox_exit_process(ret);
			}
		}

		version(OSX) export extern(C)
		noreturn main() {
			vox_init();
			i32 ret = vox_main(null);
			vox_exit_process(ret);
		}

		version(WebAssembly) {
			version(WASI) {
				export extern(C)
				void _start() {
					vox_init();
					i32 ret = vox_main(null);
					proc_exit(ret);
				}
			} else {
				export extern(C)
				void _start() {
					vox_init();
					i32 ret = vox_main(null);
				}
			}
		}
	}

	version(VANILLA_D)
	i32 main(string[] args) {
		vox_init();
		return vox_main(args);
	}
}

export extern(C) void vox_init() {
	version(NO_DEPS) __init_time();
}

version(SHARED_LIB) {
	version(Windows) extern(System) bool DllMain(void* instance, u32 reason, void* reserved) {
		return true;
	}
}

version(linux)
noreturn vox_exit_process(u32 exitCode) {
	import vox.lib.sys.syscall : syscall, sys_exit_group;
	syscall(sys_exit_group, exitCode);
	assert(0);
}

version(OSX)
noreturn vox_exit_process(u32 exitCode) {
	import vox.lib.sys.syscall : syscall, sys_exit;
	syscall(sys_exit, exitCode);
	assert(0);
}

version(Windows)
noreturn vox_exit_process(u32 exitCode) {
	import vox.lib.sys.os.windows.bind : ExitProcess;
	ExitProcess(exitCode);
}

version(WebAssembly) {
	pragma(LDC_intrinsic, "llvm.trap")
	noreturn vox_llvm_trap() @nogc nothrow;

	version(WASI) {
		noreturn vox_exit_process(u32 exitCode) @nogc nothrow {
			proc_exit(exitCode);
		}
	} else {
		noreturn vox_exit_process(u32 exitCode) @nogc nothrow {
			vox_llvm_trap();
		}
	}
}
