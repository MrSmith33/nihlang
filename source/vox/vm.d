/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm;

import vox.lib;

@nogc nothrow:


void testVM() {
	VoxAllocator allocator;

	CodeBuilder b = CodeBuilder(&allocator);

	b.emit_store_m64(2, 1);
	b.emit_store_m64(3, 2);
	b.emit_store_m64(4, 3);
	b.emit_load_m64(0, 4);
	b.emit_ret();

	VmFunction func = {
		code : b.code,
		numCallerRegisters : 2,
		numLocalRegisters : 0,
	};

	VmState vm = {
		allocator : &allocator,
		canStoreToStaticMem : true,
		ptrSize : 8,
	};

	vm.staticMemory.voidPut(allocator, 64*1024);
	vm.heapMemory.voidPut(allocator, 64*1024);
	vm.stackMemory.voidPut(allocator, 64*1024);
	vm.heapAllocations.voidPut(allocator, 1); // skip null pointer

	AllocationId funcId   = vm.addFunction(func);
	AllocationId staticId = vm.addStaticAllocation(8, 1);
	AllocationId heapId   = vm.addHeapAllocation(8, 1);
	AllocationId stackId  = vm.addStackAllocation(8, 1);

	disasm(func.code[]);

	vm.pushRegisters(1); // result register
	vm.pushRegister(VmRegister.makePtr(0, funcId));   // argument
	vm.pushRegister(VmRegister.makePtr(0, staticId)); // argument
	vm.pushRegister(VmRegister.makePtr(0, heapId));   // argument
	vm.pushRegister(VmRegister.makePtr(0, stackId));  // argument
	vm.call(funcId);
	vm.runVerbose();
	writefln("result %s", vm.getRegister(0));
}

struct CodeBuilder {
	@nogc nothrow:
	VoxAllocator* allocator;
	Array!u8 code;

	void emit_ret() {
		code.put(*allocator, VmOpcode.ret);
	}

	void emit_const_s8(u8 dst, i8 val) {
		code.put(*allocator, VmOpcode.const_s8);
		code.put(*allocator, dst);
		code.put(*allocator, val);
	}

	void emit_add_i64(u8 dst, u8 src0, u8 src1) {
		code.put(*allocator, VmOpcode.add_i64);
		code.put(*allocator, dst);
		code.put(*allocator, src0);
		code.put(*allocator, src1);
	}

	void emit_mov(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.mov);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_load_m64(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.load_m64);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}

	void emit_store_m64(u8 dst, u8 src) {
		code.put(*allocator, VmOpcode.store_m64);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}
}

struct VmFunction {
	@nogc nothrow:
	Array!u8 code;
	// result registers followed by argument registers
	u8 numCallerRegisters;
	u8 numLocalRegisters;
}

struct VmFrame {
	VmFunction* func;
	u32 ip;
	// index of the first register
	u32 firstRegister;
}

struct VmState {
	@nogc nothrow:

	bool isRunning = true;
	bool isTrap; // must be checked on return

	u8 ptrSize; // 4 or 8
	bool canStoreToStaticMem;


	VoxAllocator* allocator;
	Array!Allocation staticAllocations;
	Array!Allocation heapAllocations;
	Array!Allocation stackAllocations;
	Array!u8 staticMemory;
	Array!u8 heapMemory;
	Array!u8 stackMemory;
	u32 staticMemUsed;
	u32 heapMemUsed;
	u32 stackMemUsed;
	Array!VmFunction functions;
	Array!VmFrame frames;
	Array!VmRegister registers;


	AllocationId addFunction(VmFunction func) {
		u32 index = functions.length;
		functions.put(*allocator, func);
		u32 generation = 0;
		return AllocationId(index, generation, AllocationKind.func_id);
	}

	AllocationId addStaticAllocation(u32 size, u32 alignment) {
		u32 index = staticAllocations.length;
		u32 offset = staticMemUsed;
		staticMemUsed += size;
		if (staticMemUsed >= staticMemory.length) panic("Out of static memory");
		staticMemory.voidPut(*allocator, size);
		staticAllocations.put(*allocator, Allocation(offset, size));
		u32 generation = 0;
		return AllocationId(index, generation, AllocationKind.static_mem);
	}

	AllocationId addHeapAllocation(u32 size, u32 alignment) {
		u32 index = heapAllocations.length;
		u32 offset = heapMemUsed;
		heapMemUsed += size;
		if (heapMemUsed >= heapMemory.length) panic("Out of heap memory");
		heapMemory.voidPut(*allocator, size);
		heapAllocations.put(*allocator, Allocation(offset, size));
		u32 generation = 0;
		return AllocationId(index, generation, AllocationKind.heap_mem);
	}

	AllocationId addStackAllocation(u32 size, u32 alignment) {
		u32 index = stackAllocations.length;
		u32 offset = stackMemUsed;
		stackMemUsed += size;
		if (stackMemUsed >= stackMemory.length) panic("Out of stack memory");
		stackMemory.voidPut(*allocator, size);
		stackAllocations.put(*allocator, Allocation(offset, size));
		u32 generation = 0;
		return AllocationId(index, generation, AllocationKind.stack_mem);
	}

	void pushRegisters(u32 numRegisters) {
		registers.voidPut(*allocator, numRegisters);
	}

	void pushRegister_u64(u64 val) {
		registers.put(*allocator, VmRegister(val));
	}

	void pushRegister(VmRegister val) {
		registers.put(*allocator, val);
	}

	VmRegister getRegister(u32 index) {
		if(index >= registers.length) panic("Invalid register index (%s), only %s registers exist", index, registers.length);
		return registers[index];
	}

	void call(AllocationId funcId) {
		if(funcId.index >= functions.length) panic("Invalid function index (%s), only %s functions exist", funcId.index, functions.length);
		if(funcId.kind != AllocationKind.func_id) panic("Invalid AllocationId kind, expected func_id, got %s", allocationKindString[funcId.kind]);
		VmFunction* func = &functions[funcId.index];
		VmFrame frame = {
			func : func,
			ip : 0,
		};
		frames.put(*allocator, frame);
		registers.voidPut(*allocator, func.numLocalRegisters);
	}

	void run() {
		while(isRunning) step();
	}

	void runVerbose() {
		writeln("---");
		printRegs();
		while(isRunning) {
			u32 ipCopy = frames.back.ip;
			disasmOne(frames.back.func.code[], ipCopy);
			step();
			printRegs();
		}
		writeln("---");
	}

	void step() {
		if(frames.length == 0) panic("step: Frame stack is empty");
		VmFrame* frame = &frames.back();
		//enforce(frame.ip < frame.func.code.length, "IP is out of bounds (%s), code is %s bytes", frame.ip, frame.func.code.length);
		VmOpcode op = cast(VmOpcode)frame.func.code[frame.ip++];

		final switch(op) with(VmOpcode) {
			case ret:
				registers.unput(frame.func.numLocalRegisters);
				frames.unput(1);

				if (frames.length == 0) isRunning = false;
				return;

			case mov:
				u8 dst = frame.func.code[frame.ip++];
				u8 src = frame.func.code[frame.ip++];
				registers[frame.firstRegister + dst] = registers[frame.firstRegister + src];
				return;

			case add_i64:
				VmRegister* dst  = &registers[frame.firstRegister + frame.func.code[frame.ip++]];
				VmRegister* src0 = &registers[frame.firstRegister + frame.func.code[frame.ip++]];
				VmRegister* src1 = &registers[frame.firstRegister + frame.func.code[frame.ip++]];
				dst.as_u64 = src0.as_u64 + src1.as_u64;
				dst.pointer = src0.pointer;
				if (src1.pointer.isDefined) panic("add.i64 can only contain pointers in the first argument. (%s) Instr %s", *src1, frame.ip-3);
				return;

			case const_s8:
				VmRegister* dst  = &registers[frame.firstRegister + frame.func.code[frame.ip++]];
				i8 src = frame.func.code[frame.ip++];
				dst.as_s64 = src;
				return;

			case load_m8:
			case load_m16:
			case load_m32:
			case load_m64:
				u32 size = 1 << (op - load_m8);

				VmRegister* dst = &registers[frame.firstRegister + frame.func.code[frame.ip++]];
				VmRegister* src = &registers[frame.firstRegister + frame.func.code[frame.ip++]];
				if (src.pointer.isUndefined) panic("Reading from non-pointer value");

				Allocation* alloc;
				u8* memory;
				pointerMemoryLoad(src, alloc, memory);

				u64 offset = src.as_u64;
				if (offset + size > alloc.size)
					panic("Reading past the end of the allocation. offset %s, size %s", offset, alloc.size);

				switch(op) {
					case load_m8:  dst.as_u64 = *cast( u8*)(memory+alloc.offset+offset); break;
					case load_m16: dst.as_u64 = *cast(u16*)(memory+alloc.offset+offset); break;
					case load_m32: dst.as_u64 = *cast(u32*)(memory+alloc.offset+offset); break;
					case load_m64: dst.as_u64 = *cast(u64*)(memory+alloc.offset+offset); break;
					default: assert(false);
				}

				if (ptrSize == size) {
					// this can be a pointer load
					dst.pointer = alloc.relocations.get(cast(u32)offset);
				}
				break;

			case store_m8:
			case store_m16:
			case store_m32:
			case store_m64:
				u32 size = 1 << (op - store_m8);

				VmRegister* dst  = &registers[frame.firstRegister + frame.func.code[frame.ip++]];
				VmRegister* src  = &registers[frame.firstRegister + frame.func.code[frame.ip++]];
				if (dst.pointer.isUndefined) panic("Writing to non-pointer value %s", *dst);

				Allocation* alloc;
				u8* memory;
				pointerMemoryStore(dst, alloc, memory);

				u64 offset = dst.as_u64;
				if (offset + 8 > alloc.size) panic("Writing past the end of the allocation.");

				switch(op) {
					case store_m8:  *cast( u8*)(memory+alloc.offset+offset) = src.as_u8; break;
					case store_m16: *cast(u16*)(memory+alloc.offset+offset) = src.as_u16; break;
					case store_m32: *cast(u32*)(memory+alloc.offset+offset) = src.as_u32; break;
					case store_m64: *cast(u64*)(memory+alloc.offset+offset) = src.as_u64; break;
					default: assert(false);
				}

				if (ptrSize == size) {
					// this can be a pointer store
					if (src.pointer.isDefined)
						alloc.relocations.put(*allocator, cast(u32)offset, src.pointer);
					else
						alloc.relocations.remove(*allocator, cast(u32)offset);
				}
				break;
		}
	}

	void pointerMemoryLoad(VmRegister* src, ref Allocation* alloc, ref u8* memory) {
		final switch(src.pointer.kind) with(AllocationKind) {
			case heap_mem:
				alloc = &heapAllocations[src.pointer.index];
				memory = heapMemory[].ptr;
				break;
			case static_mem:
				alloc = &staticAllocations[src.pointer.index];
				memory = staticMemory[].ptr;
				break;
			case stack_mem:
				alloc = &stackAllocations[src.pointer.index];
				memory = stackMemory[].ptr;
				break;
			case func_id: panic("Cannot read from function pointer %s", *src);
		}
	}

	void pointerMemoryStore(VmRegister* dst, ref Allocation* alloc, ref u8* memory) {
		final switch(dst.pointer.kind) with(AllocationKind) {
			case heap_mem:
				alloc = &heapAllocations[dst.pointer.index];
				memory = heapMemory[].ptr;
				break;
			case static_mem:
				alloc = &staticAllocations[dst.pointer.index];
				memory = staticMemory[].ptr;
				if (!canStoreToStaticMem) panic("Writing to static memory is disabled");
				break;
			case stack_mem:
				alloc = &stackAllocations[dst.pointer.index];
				memory = stackMemory[].ptr;
				break;
			case func_id: panic("Cannot store to function pointer %s", *dst);
		}
	}

	void printRegs() {
		write("     [");
		foreach(i, reg; registers) {
			if (i > 0) write(", ");
			write(reg);
		}
		writeln("]");
	}
}

// Register can contain 0 or 1 pointer, so instead of storing a hashmap of relocations
// we store a single AllocationId
// vector registers are forbidden to store pointers
align(16)
struct VmRegister {
	@nogc nothrow:
	union {
		u64 as_u64; // init union to 0
		u8  as_u8;
		u16 as_u16;
		u32 as_u32;
		i8  as_s8;
		i16 as_s16;
		i32 as_s32;
		i64 as_s64;
		f32 as_f32;
		f64 as_f64;
	}
	AllocationId pointer;

	void toString(scope SinkDelegate sink, FormatSpec spec) @nogc nothrow const {
		if (pointer.isDefined) {
			sink.formattedWrite("%s%s+%s", allocKindStrings[pointer.kind], pointer.index, as_u64);
		} else {
			sink.formatValue(as_u64);
		}
	}

	static VmRegister makePtr(u64 offset, AllocationId alloc) {
		VmRegister r = {
			as_u64 : offset,
			pointer : alloc,
		};
		return r;
	}
}

//import std.bitmanip : bitfields;
struct AllocationId {
	@nogc nothrow:
	this(u32 index, u32 generation, AllocationKind kind) {
		this.index = index;
		this._generation = (generation & ((1 << 30) - 1)) | (kind << 30);
	}

	union {
		u64 payload;
		struct {
			u32 index;
			private u32 _generation;
		}
	}
	//mixin(bitfields!(
	//	u32,           "generation", 30,
	//	AllocationKind,      "kind",  2,
	//));

	u32 generation() const {
		return cast(u32)(_generation & ((1 << 30) - 1));
	}

	// kind: heap, static, function, stack
	AllocationKind kind() const {
		return cast(AllocationKind)(_generation >> 30);
	}

	bool isDefined() const { return payload != 0; }
	bool isUndefined() const { return payload == 0; }
}

immutable string[4] allocKindStrings = [
	"h", "g", "f", "s"
];

struct Allocation {
	u32 offset;
	u32 size;
	HashMap!(u32, AllocationId, u32.max) relocations;
}

void disasm(u8[] code) {
	u32 ip;
	while(ip < code.length) {
		disasmOne(code, ip);
	}
}

void disasmOne(u8[] code, ref u32 ip) {
	auto addr = ip++;
	VmOpcode op = cast(VmOpcode)code[addr];
	final switch(op) with(VmOpcode) {
		case ret:
			writefln("%04x ret", addr);
			break;

		case mov:
			u8 dst = code[ip++];
			u8 src = code[ip++];
			writefln("%04x mov r%s, r%s", addr, dst, src);
			break;

		case add_i64:
			u8 dst  = code[ip++];
			u8 src0 = code[ip++];
			u8 src1 = code[ip++];
			writefln("%04x add.i64 r%s, r%s, r%s", addr, dst, src0, src1);
			break;

		case const_s8:
			u8 dst = code[ip++];
			i8 src = code[ip++];
			writefln("%04x const.s8 r%s, %s", addr, dst, src);
			break;

		case load_m8:
		case load_m16:
		case load_m32:
		case load_m64:
			u32 size_bits = (1 << (op - load_m8)) * 8;
			u8 dst = code[ip++];
			i8 src = code[ip++];
			writefln("%04x load.m%s r%s, [r%s]", addr, size_bits, dst, src);
			break;

		case store_m8:
		case store_m16:
		case store_m32:
		case store_m64:
			u32 size_bits = (1 << (op - store_m8)) * 8;
			u8 dst = code[ip++];
			i8 src = code[ip++];
			writefln("%04x store.m%s [r%s], r%s", addr, size_bits, dst, src);
			break;
	}
}

enum AllocationKind : u8 {
	heap_mem,
	static_mem,
	func_id,
	stack_mem,
}

string[4] allocationKindString = [
	"heap",
	"static",
	"function",
	"stack",
];

// m - anything
// v - simd vectors
// f - float
// i - signed or unsigned int
// u - unsigned int
// s - signed int

enum VmOpcode : u8 {
	ret,

	mov,

	add_i64,

	const_s8,

	load_m8,
	load_m16,
	load_m32,
	load_m64,

	store_m8,
	store_m16,
	store_m32,
	store_m64,
}

