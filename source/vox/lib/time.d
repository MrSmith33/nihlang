/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.time;

import vox.lib;
@nogc nothrow:

version(VANILLA_D) {
	MonoTime currTime() {
		import core.time : CoreMonoTime = MonoTime;
		return MonoTime(CoreMonoTime.currTime().ticks);
	}
}

struct MonoTime {
	@nogc nothrow:

	u64 ticks;

	Duration opBinary(string op)(MonoTime rhs) const pure
		if (op == "-")
	{
		return Duration(ticks - rhs.ticks);
	}

	static i64 ticksPerSecond() {
		version(NO_DEPS) {
			return _ticksPerSecond;
		}
		version(VANILLA_D) {
			import core.time : CoreMonoTime = MonoTime;
			return CoreMonoTime.ticksPerSecond;
		}
	}
}

struct Duration {
	@nogc nothrow:

	i64 ticks;

	void toString(scope SinkDelegate sink, FormatSpec spec) const {
		sink.formattedWrite("%ms", cast(double)ticks / MonoTime.ticksPerSecond);
	}
}

version(NO_DEPS):

MonoTime currTime() {
	version(Windows) {
		long ticks = void;
		QueryPerformanceCounter(&ticks);
		return MonoTime(ticks);
	}
	else version (OSX) {
		return MonoTime(mach_absolute_time());
	}
	else version(Posix) {
		timespec ts = void;
        auto errno = clock_gettime(CLOCK_MONOTONIC, &ts);
		if (errno != 0) panic("clock_gettime errno is %s", errno);
        return MonoTime(ts.tv_sec * 1_000_000_000L + ts.tv_nsec);
	}
	else version(WASI) {
		import vox.lib.system.wasm_wasi;
		u64 time;
		__wasi_errno_t errno = clock_time_get(WASI_CLOCKID.MONOTONIC, 1, &time);
		if (errno != 0) panic("clock_time_get errno is %s", errno);
		return MonoTime(time);
	}
	else version(WebAssembly) {
		return MonoTime(getTimeNs());
	}
	else static assert(false, "Unsupported platform");
}

extern(C) void __init_time() {
	if (_ticksPerSecond != 0) panic("_ticksPerSecond is already initialized");
	     version(Windows) QueryPerformanceFrequency(cast(long*)&_ticksPerSecond);
	else version(OSX) *cast(long*)&_ticksPerSecond = mach_ticks_per_second();
	else version(Posix) *cast(long*)&_ticksPerSecond = 1_000_000_000L;
	else version(WASI)  *cast(long*)&_ticksPerSecond = 1_000_000_000L;
	else version(WebAssembly)  *cast(long*)&_ticksPerSecond = 1_000_000_000L;
}

immutable i64 _ticksPerSecond;
