/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.mutex;

import vox.lib.atomic;
import vox.lib.error : panic;
import vox.lib.types;

@nogc nothrow @system:

struct Mutex {
	@nogc nothrow @system:

	enum State : u32 { unlocked, locked, contested };
	State state;

	bool tryLock() {
		return cas!(MemoryOrder.acq, MemoryOrder.acq)(&state, State.unlocked, State.locked);
	}

	void lock() {
		if (tryLock()) return;
		while (atomicExchange(&state, State.contested) != State.unlocked) {
			wait(&state, State.contested);
		}
	}

	void unlock() {
		if (atomicExchange!(MemoryOrder.rel)(&state, State.unlocked) == State.contested) {
			notifyOne(&state);
		}
	}
}

struct RecursiveMutex {
	import vox.lib.thread;
	enum State : u32 { unlocked, locked, contested };
	State state;
	u32 counter;
	Tid owner;

	private bool tryLockState() {
		return cas!(MemoryOrder.acq, MemoryOrder.acq)(&state, State.unlocked, State.locked);
	}

	bool tryLock(Tid tid) {
		if(tid == Tid(0)) panic("tid == 0");
		if (owner == tid) {
			// recursion
			assert(counter > 0);
			++counter;
			return true;
		}
		if (tryLockState()) {
			assert(owner == Tid(0));
			assert(counter == 0);
			owner = tid;
			++counter;
			return true;
		}
		return false;
	}

	void lock(Tid tid) {
		if(tid == Tid(0)) panic("tid == 0");
		if (owner == tid) {
			// recursion
			assert(counter > 0);
			++counter;
			return;
		}

		if (tryLockState()) goto first_lock;

		while (atomicExchange(&state, State.contested) != State.unlocked) {
			wait(&state, State.contested);
		}

	first_lock:

		assert(owner == Tid(0));
		assert(counter == 0);
		owner = tid;
		++counter;
	}

	void unlock() {
		--counter;
		if (counter == 0) {
			owner = Tid(0);
			if (atomicExchange!(MemoryOrder.rel)(&state, State.unlocked) == State.contested) {
				notifyOne(&state);
			}
		}
	}
}
