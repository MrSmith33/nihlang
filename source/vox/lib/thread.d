/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.thread;

@nogc nothrow:

import vox.lib;

alias ThreadFunc = extern(C) u32 function(void*);

version(Windows) {
	enum threads_supported = true;
	void spawnThread(ref Thread thread, ThreadFunc func, void* userData) {
		HANDLE handle = CreateThread(
			null,     // default security attributes
			0,        // use default stack size
			func,     // thread function pointer
			userData, // user data
			0,        // use default creation flags
			null);    // returns the thread identifier

		if (handle == null) {
			auto err = GetLastError();
			panic("spawnThread failed. CreateThread failed. Error: %s", err);
		}

		thread.handle = handle;
		thread.tid = GetThreadId(handle);
	}

	struct Thread {
		@nogc nothrow:
		HANDLE handle;
		u32 tid;

		void join() {
			WaitForSingleObject(handle, INFINITE);
			bool success = CloseHandle(handle);
			if (!success) {
				auto err = GetLastError();
				panic("Thread CloseHandle failed. handle = %s. Error: %s", handle, err);
			}
			handle = null;
		}
	}
} else version(WASI) {
	enum threads_supported = true;

	import ldc.attributes;
	import vox.lib.system.wasm_all;
	import vox.lib.system.wasm_wasi;

	enum MiB = 1024 * 1024;

	void spawnThread(ref Thread thread, ThreadFunc func, void* userData) {
		usz stackPtr = wasm_memory_grow(0, thread.stackSize / WASM_PAGE) * WASM_PAGE;
		// Stack grows to lower addresses in LLVM
		stackPtr += thread.stackSize;
		thread.stackPtr = cast(void*)stackPtr;
		thread.func = func;
		thread.userData = userData;
		thread.status = 0;
		thread.isFinished = 0;
		atomicFence();
		thread.tid = thread_spawn(&thread);
		if (thread.tid < 0) {
			panic("WASI thread_spawn failed. tid = %s", thread.tid);
		}
	}

	struct Thread {
		@nogc nothrow:

		// TODO: reuse stack memory after thread is stopped for new threads/other allocations
		void* stackPtr;
		usz stackSize = 1*MiB;
		ThreadFunc func;
		void* userData;
		u32 tid;

		private u32 status = 0;
		private u32 isFinished = 0;

		void join() {
			wait(&isFinished, 0);
		}
	}

	// When wasi::thread-spawn is called, the WASM runtime calls wasi_thread_start in a new thread
	// It sets __stack_pointer of a newly spawned thread and calls __wasi_thread_start_user
	// It is important to mark this as naked, otherwise compiler may insert
	// a read from __stack_pointer before it gets initialized
	@naked export extern(C) void wasi_thread_start(i32 tid, Thread* thread) {
		import ldc.llvmasm;
		__asm("
			local.get 1                # Thread* thread
			i32.load  0#offset         # thread.stackPtr
			global.set __stack_pointer # __stack_pointer = thread.stackPtr

			local.get 0                # tid
			local.get 1                # start_arg
			call __wasi_thread_start_user
			return", "");
			// compiler adds unreachable after call
			// add return to avoid hitting it
	}

	private extern(C) void __wasi_thread_start_user(i32 tid, Thread* thread) {
		atomicStore(thread.tid, tid);
		u32 status = thread.func(thread.userData);
		atomicStore(thread.status, status);
		atomicFence();
		atomicStore(thread.isFinished, 1);
		notifyAll(&thread.isFinished);
	}
} else {
	enum threads_supported = false;
	Thread spawnThread(ThreadFunc func, void* userData) {
		panic("Threads are not implemented on this target");
	}

	struct Thread {
		@nogc nothrow:
		void join() {
			panic("Threads are not implemented on this target");
		}
	}
}
