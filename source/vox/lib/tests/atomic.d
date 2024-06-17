/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.tests.atomic;

@nogc nothrow:

import vox.lib.types;
import vox.lib.io;
import vox.lib.thread;

void runTests() {
	testWaitNotify();
}

void testWaitNotify() {
	import vox.lib.atomic: atomicFence, atomicStore, notifyOne, wait;

	__gshared u32 g_flag;
	__gshared void* g_arg;

	extern(C) u32 threadFunc(void* userData) {
		// store user pointer
		g_arg = userData;
		// store fence
		atomicFence();
		// notify the main
		atomicStore(g_flag, 1);
		notifyOne(&g_flag);
		// returning from threadFunc terminates only this thread
		return 18;
	}

	Thread thread;
	u32 userData = 42;
	spawnThread(thread, &threadFunc, cast(void*)&userData);
	wait(&g_flag, 0);
	// load fence
	atomicFence();
	// check the user pointer
	assert(g_arg == &userData);
	thread.join;
	// assert(thread.status == 18);
	writefln("testWaitNotify success");
}
