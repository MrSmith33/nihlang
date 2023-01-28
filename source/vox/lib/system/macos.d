/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.system.macos;

version(OSX) version(X86_64) @nogc nothrow @system:

import vox.lib;

version(NO_DEPS)
long mach_ticks_per_second() {
    mach_timebase_info_data_t info;
    if (mach_timebase_info(&info) != 0) {
        panic("mach_timebase_info() did not succeed");
    }

    long scaledDenom = 1_000_000_000L * info.denom;
    if (scaledDenom % info.numer != 0) {
        panic("Ration is not dividable without remainder");
    }
    return scaledDenom / info.numer;
}

struct mach_timebase_info_data_t {
    uint numer;
    uint denom;
}


extern(C):

version(NO_DEPS) {
	ulong mach_absolute_time();
	int mach_timebase_info(mach_timebase_info_data_t*);
	// ulong clock_gettime_nsec_np(clockid_t clock_id);
}
