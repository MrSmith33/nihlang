/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.system.wasi;

version(WASI) @nogc nothrow @system:

import vox.lib.types;
import ldc.attributes;

void writeString(const(char)[] str) {
	__wasi_ciovec_t[1] bufs = [__wasi_ciovec_t(cast(u8*)str.ptr, str.length)];
	usize result;
	__wasi_errno_t err = fd_write(1, bufs.ptr, bufs.length, &result);
}


extern(C):


// Types

/// A region of memory for scatter/gather writes.
struct __wasi_ciovec_t {
	/// The address of the buffer to be written.
	const u8* buf;
	/// The length of the buffer to be written.
	usize buf_len;
}

alias __wasi_errno_t = u16;
alias __wasi_fd_t = i32;


// Functions

@llvmAttr("wasm-import-module", "wasi_unstable"):

/// Write to a file descriptor.
/// Note: This is similar to `writev` in POSIX.
//wasi_unstable fd_write
__wasi_errno_t fd_write(
	__wasi_fd_t fd,
	/// List of scatter/gather vectors from which to retrieve data.
	const __wasi_ciovec_t* iovs,
	/// The length of the array pointed to by `iovs`.
	usize iovs_len,
	usize* retptr0
);

/// Terminate the process normally. An exit code of 0 indicates successful
/// termination of the program. The meanings of other values is dependent on
/// the environment.
noreturn proc_exit(
	/// The exit code returned by the process.
	u32 rval
);
