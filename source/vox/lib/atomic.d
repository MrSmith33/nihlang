/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.atomic;

import vox.lib.types;

version(LDC) {
	public import core.atomic;
}

@nogc nothrow @system:

version(WebAssembly) {
	import vox.lib.system.wasm_all;

	// Wake up a single thread waiting on the address
	void notify(void* address) {
		wasm_memory_atomic_notify(cast(usz*)address, 1);
	}
	// Wake all threads waiting on the address
	void notifyAll(void* address) {
		// spec states that max number of threads is u32.max
		// therefore this should wake all potential waiters
		wasm_memory_atomic_notify(cast(u32*)address, u32.max);
	}

	void wait(void* onAddress, u32 untilThisChanges) {
		wasm_memory_atomic_wait32(cast(u32*)onAddress, untilThisChanges, -1);
	}
	void wait(void* onAddress, u64 untilThisChanges) {
		wasm_memory_atomic_wait64(cast(u64*)onAddress, untilThisChanges, -1);
	}

	void wait(void* onAddress, u32 untilThisChanges, i64 timeout_ns) {
		wasm_memory_atomic_wait32(cast(u32*)onAddress, untilThisChanges, timeout_ns);
	}
	void wait(void* onAddress, u64 untilThisChanges, i64 timeout_ns) {
		wasm_memory_atomic_wait64(cast(u64*)onAddress, untilThisChanges, timeout_ns);
	}
}

version (Windows) {
	import vox.lib.system.windows;

	// Wake up a single thread waiting on the address
	void notify(void* address) {
		RtlWakeAddressSingle(address);
	}
	// Wake all threads waiting on the address
	void notifyAll(void* address) {
		RtlWakeAddressAll(address);
	}

	void wait(void* onAddress, u32 untilThisChanges) {
		u32 CompareAddress = untilThisChanges;
		RtlWaitOnAddress(onAddress, &CompareAddress, CompareAddress.sizeof, null);
	}
	void wait(void* onAddress, u64 untilThisChanges) {
		u64 CompareAddress = untilThisChanges;
		RtlWaitOnAddress(onAddress, &CompareAddress, CompareAddress.sizeof, null);
	}
}

version(linux) {
	import vox.lib.system.linux;

	// Wake up a single thread waiting on the address
	void notify(void* address) {
		futex_wake(cast(u32*)address, 1);
	}
	// Wake all threads waiting on the address
	void notifyAll(void* address) {
		futex_wake(cast(u32*)address, u32.max);
	}

	void wait(void* onAddress, u32 untilThisChanges) {
		futex_wait(cast(u32*)onAddress, untilThisChanges, null);
	}
}

version(DigitalMars) {
	private {
		enum : int {
			AX, BX, CX, DX, DI, SI, R8, R9
		}

		immutable string[4][8] regNames = [
			[ "AL", "AX", "EAX", "RAX" ],
			[ "BL", "BX", "EBX", "RBX" ],
			[ "CL", "CX", "ECX", "RCX" ],
			[ "DL", "DX", "EDX", "RDX" ],
			[ "DIL", "DI", "EDI", "RDI" ],
			[ "SIL", "SI", "ESI", "RSI" ],
			[ "R8B", "R8W", "R8D", "R8" ],
			[ "R9B", "R9W", "R9D", "R9" ],
		];

		template TypeToRegSize(T) {
			static if (T.sizeof == 1)
				enum TypeToRegSize = 0;
			else static if (T.sizeof == 2)
				enum TypeToRegSize = 1;
			else static if (T.sizeof == 4)
				enum TypeToRegSize = 2;
			else static if (T.sizeof == 8)
				enum TypeToRegSize = 3;
			else
				static assert(false, "Unsupported type");
		}

		enum RES = AX;
		version (Windows) {
			// C args: cx dx r8 r9
			enum ARG0 = CX;
			enum ARG1 = DX;
			enum ARG2 = R8;
			enum ARG3 = R9;
		} else {
			// C args: di si dx cx
			enum ARG0 = DI;
			enum ARG1 = SI;
			enum ARG2 = DX;
			enum ARG3 = CX;
		}

		enum R(int reg, T = size_t) = regNames[reg][TypeToRegSize!T];
	}

	version (D_InlineAsm_X86_64) {
	} else static assert (false, "Unsupported architecture.");

	enum MemoryOrder : int {
		raw = 0,
		acq = 2,
		rel = 3,
		acq_rel = 4,
		seq = 5,
	}

	extern(C)
	T atomicFetchAdd(MemoryOrder order = MemoryOrder.seq, T)(ref T dest, T value) pure nothrow @nogc @trusted {
		mixin("asm pure nothrow @nogc @trusted {
			naked;
			lock; xadd[", R!(ARG0,T), "], ", R!(ARG1,T), ";
			mov ", R!(RES,T), ", ", R!(ARG1,T), ";
			ret;
		}");
	}

	extern(C)
	T cmpxchg
		(MemoryOrder succ = MemoryOrder.seq, MemoryOrder fail = MemoryOrder.seq, T)
		(T* here, T ifThis, T writeThis)
		pure nothrow @nogc @trusted
	{
		cas!(succ, fail)(here, &ifThis, writeThis);
		return ifThis;
	}

	extern(C)
	bool cas
		(MemoryOrder succ = MemoryOrder.seq, MemoryOrder fail = MemoryOrder.seq, T)
		(T* here, T* ifThis, T writeThis)
		pure nothrow @nogc @trusted
	{
		// mov AX, [ifThis]
		// lock; cmpxchg [here], writeThis
		// mov success, AL
		// mov [ifThis], RAX
		mixin("asm pure nothrow @nogc @trusted {
			naked;
			mov ", R!(AX, T), ", [", R!(ARG1,T), "];
			lock; cmpxchg [", R!(ARG0,T), "], ", R!(ARG2,T), ";
			setz AL;
			mov [", R!(ARG1,T), "], ", R!(AX, T), ";
			ret;
		}");
	}

	extern(C)
	bool cas
		(MemoryOrder succ = MemoryOrder.seq, MemoryOrder fail = MemoryOrder.seq, T)
		(T* here, const T ifThis, T writeThis)
		pure nothrow @nogc @trusted
	{
		// mov AX, ifThis
		// lock; cmpxchg [here], writeThis
		// ret success
		mixin("asm pure nothrow @nogc @trusted {
			naked;
			mov ", R!(AX, T), ", ", R!(ARG1,T), ";
			lock; cmpxchg [", R!(ARG0,T), "], ", R!(ARG2,T), ";
			setz AL;
			ret;
		}");
	}

	alias casWeak = cas;

	extern(C)
	T atomicExchange
		(MemoryOrder order = MemoryOrder.seq, T)(T* here, T exchangeWith)
		pure nothrow @nogc @trusted
	{
		// lock; xchg [here], exchangeWith
		// mov AX, exchangeWith
		mixin("asm pure nothrow @nogc @trusted {
			naked;
			lock; xchg [", R!(ARG0,T), "], ", R!(ARG1,T), ";
			mov ", R!(AX, T), ", ", R!(ARG1,T), ";
			ret;
		}");
	}

	pure nothrow @nogc @safe
	void atomicFence(MemoryOrder order = MemoryOrder.seq)() {
		static if (order != MemoryOrder.raw)
		asm pure nothrow @nogc @trusted {
			naked;
			mfence;
			ret;
		}
	}

	extern(C)
	T atomicLoad(MemoryOrder ms = MemoryOrder.seq, T)(ref const T val) {
		return val;
	}

	extern(C)
	void atomicStore(MemoryOrder ms = MemoryOrder.seq, T)(ref T val, T newval) {
		val = newval;
	}
}
