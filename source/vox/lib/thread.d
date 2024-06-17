/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.thread;

@nogc nothrow:

import vox.lib;

alias ThreadFunc = extern(C) u32 function(void*);

struct Tid {
	u32 value;
}
enum MiB = 1024 * 1024;

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
		thread.tid = GetThreadId(handle).Tid;
	}

	struct Thread {
		@nogc nothrow:
		HANDLE handle;
		Tid tid;

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

	void spawnThread(ref Thread thread, ThreadFunc func, void* userData) {
		usz stackPtr = wasm_memory_grow(0, thread.stackSize / WASM_PAGE) * WASM_PAGE;
		// Stack grows to lower addresses in LLVM
		usz stackTop = stackPtr + thread.stackSize;
		thread.stackTop = cast(void*)stackTop;
		thread.func = func;
		thread.userData = userData;
		thread.status = 0;
		thread.isFinished = 0;
		atomicFence();
		auto tid = thread_spawn(&thread);
		if (tid < 0) {
			panic("WASI thread_spawn failed. tid = %s", tid);
		}
		thread.tid = Tid(tid);
	}

	struct Thread {
		@nogc nothrow:

		// TODO: reuse stack memory after thread is stopped for new threads/other allocations
		void* stackTop;
		usz stackSize = 1*MiB;
		ThreadFunc func;
		void* userData;
		Tid tid;

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
			i32.load  0#offset         # thread.stackTop
			global.set __stack_pointer # __stack_pointer = thread.stackTop

			local.get 0                # tid
			local.get 1                # start_arg
			call __wasi_thread_start_user
			return", "");
			// compiler adds unreachable after __asm
			// add return to avoid hitting it
	}

	private extern(C) void __wasi_thread_start_user(i32 tid, Thread* thread) {
		atomicStore(thread.tid.value, tid);
		u32 status = thread.func(thread.userData);
		atomicStore(thread.status, status);
		atomicFence();
		atomicStore(thread.isFinished, 1);
		notifyAll(&thread.isFinished);
	}
} else version(linux) {
	import ldc.attributes;

	enum threads_supported = true;
	void spawnThread(ref Thread thread, ThreadFunc func, void* userData) {
		import vox.lib.system.posix;
		void* p = mmap(null, thread.stackSize, PROT_READ | PROT_WRITE,
			MAP_PRIVATE | MAP_ANON, -1, 0);

		if (cast(usz)p > cast(usz)(-4096UL)) {
			panic("spawnThread failed. mmap failed. Error: %s", -cast(i32)p);
		}

		thread.func = func;
		thread.userData = userData;
		thread.status = 0;
		thread.isFinished = 0;

		usz length = thread.stackSize / Thread.sizeof;
		auto buf = p[0..thread.stackSize];
		OnStackData[] typedBuf = (cast(OnStackData*)p)[0..length];
		OnStackData* data = &typedBuf[$-1];
		*data = OnStackData(cast(void*)&__linux_thread_start_user, &thread);

		auto tid = spawnLinuxThread(data);
		if (tid < 0) {
			panic("linux thread spawn failed. tid = %s", tid);
		}

		thread.tid = Tid(tid);
	}

	private extern(C) void __linux_thread_start_user(OnStackData* data) {
		// atomicStore(thread.tid.value, tid);
		u32 status = data.thread.func(data.thread.userData);
		atomicStore(data.thread.status, status);
		atomicFence();
		atomicStore(data.thread.isFinished, 1);
		notifyAll(&data.thread.isFinished);
		import vox.lib.system.syscall : syscall, sys_exit;
		syscall(sys_exit, status);
	}

	private @naked i32 spawnLinuxThread(OnStackData* data) {
		import ldc.llvmasm;
		return __asm!i32("
			movq  %rdi, %rsi
			movl  $$0x50f00, %edi
			movl  $$56, %eax
			syscall
			movq  %rsp, %rdi",
			"={rax} ~{rax} ~{rdi} ~{rsi} ~{rdx} ~{rcx} ~{r11}");
	}

	// Data that is passed through stack to the new thread
	// First slot is always a function pointer, that is being popped of the stack
	// See: Practical libc-free threading on Linux - https://nullprogram.com/blog/2023/03/23/
	align(16) private struct OnStackData {
		void* func;     // __linux_thread_start_user
		Thread* thread;
	}

	struct Thread {
		@nogc nothrow:

		// TODO: reuse stack memory after thread is stopped for new threads/other allocations
		void* stackTop;
		usz stackSize = 1*MiB;
		ThreadFunc func;
		void* userData;
		Tid tid;

		private u32 status = 0;
		private u32 isFinished = 0;

		void join() {
			wait(&isFinished, 0);
		}
	}
} else {
	enum threads_supported = false;
	void spawnThread(ref Thread thread, ThreadFunc func, void* userData) {
		panic("Threads are not implemented on this target");
	}

	struct Thread {
		@nogc nothrow:
		void join() {
			panic("Threads are not implemented on this target");
		}
	}
}
