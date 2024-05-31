/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

/// This is for WASI only
/// Get function names from https://github.com/WebAssembly/wasi-http-proxy/blob/84438a7e776f962f58d324747d0bf0ad28112a90/phases/snapshot/docs.md
/// Get function signature from https://github.com/WebAssembly/wasi-libc/blob/main/libc-bottom-half/headers/public/wasi/api.h
module vox.lib.system.wasm_wasi;

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
// Timestamp in nanoseconds.
alias __wasi_timestamp_t = u64;


// Functions

@llvmAttr("wasm-import-module", "wasi_unstable"):

/// Write to a file descriptor.
/// Note: This is similar to `writev` in POSIX.
__wasi_errno_t fd_write(
	__wasi_fd_t fd,
	/// List of scatter/gather vectors from which to retrieve data.
	const __wasi_ciovec_t* iovs,
	/// The length of the array pointed to by `iovs`.
	usize iovs_len,
	/// Return: The number of bytes written.
	usize* nwritten
);

enum WASI_CLOCKID : u32 {
	/// The clock measuring real time. Time value zero corresponds with
	/// 1970-01-01T00:00:00Z.
	REALTIME = 0,
	/// The store-wide monotonic clock, which is defined as a clock measuring
	/// real time, whose value cannot be adjusted and which cannot have negative
	/// clock jumps. The epoch of this clock is undefined. The absolute time
	/// value of this clock therefore has no meaning.
	MONOTONIC = 1,
	/// The CPU-time clock associated with the current process.
	PROCESS_CPUTIME = 2,
	/// The CPU-time clock associated with the current thread.
	THREAD_CPUTIME = 3,
}

/// Return the resolution of a clock.
/// Implementations are required to provide a non-zero value for supported clocks. For unsupported clocks,
/// return `errno::inval`.
/// Note: This is similar to `clock_getres` in POSIX.
__wasi_errno_t clock_res_get(
	/// The clock for which to return the resolution.
	WASI_CLOCKID id,
	/// Return: The resolution of the clock, or an error if one happened. In nanoseconds.
	u64* resolution
);

/// Return the time value of a clock.
/// Note: This is similar to `clock_gettime` in POSIX.
__wasi_errno_t clock_time_get(
	/// The clock for which to return the time.
	WASI_CLOCKID id,
	/// The maximum lag (exclusive) that the returned time value may have, compared to its actual value. In nanoseconds.
	u64 precision,
	/// Return: The time value of the clock in nanoseconds
	u64* time
);

/// Terminate the process normally. An exit code of 0 indicates successful
/// termination of the program. The meanings of other values is dependent on
/// the environment.
noreturn proc_exit(
	/// The exit code returned by the process.
	u32 rval
);

// Negative result means error
@llvmAttr("wasm-import-module", "wasi")
@llvmAttr("wasm-import-name", "thread-spawn")
i32 thread_spawn(
	// A pointer to an opaque struct to be passed to the module's entry function.
	void* start_arg
);
