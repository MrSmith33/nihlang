/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

// Code common for all macos platforms (arch-independent)
module vox.lib.sys.os.macos;

public import vox.lib.sys.os.macos.syscall;


@nogc nothrow @system:

import vox.lib.types;
import vox.lib.error;

version(NO_DEPS)
long mach_ticks_per_second() {
	mach_timebase_info_data_t info;
	if (mach_timebase_info(&info) != 0) {
		panic("mach_timebase_info() did not succeed");
	}

	long scaledDenom = 1_000_000_000L * info.denom;
	if (scaledDenom % info.numer != 0) {
		panic("Number is not divisible without remainder");
	}
	return scaledDenom / info.numer;
}

struct mach_timebase_info_data_t {
	uint numer;
	uint denom;
}


extern(C):
version(NO_DEPS) {
	// /usr/lib/system/libsystem_kernel.dylib
	ulong mach_absolute_time();
	int mach_timebase_info(mach_timebase_info_data_t*);
	// ulong clock_gettime_nsec_np(clockid_t clock_id);
}

enum MAP_ANON  = 0x1000;
enum MS_SYNC   = 0x0010;
