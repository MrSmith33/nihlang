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
		readWriteMask : MemFlags.heap_RW | MemFlags.stack_RW | MemFlags.static_RW,
		ptrSize : 8,
	};

	// Reserve 64K for heap, static and stack
	vm.memories[MemoryKind.static_mem].memory.voidPut(allocator, 64*1024);
	vm.memories[MemoryKind.heap_mem].memory.voidPut(allocator, 64*1024);
	vm.memories[MemoryKind.heap_mem].allocations.voidPut(allocator, 1); // skip null pointer
	vm.memories[MemoryKind.stack_mem].memory.voidPut(allocator, 64*1024);

	AllocationId funcId   = vm.addFunction(func);
	AllocationId staticId = vm.memories[MemoryKind.static_mem].allocate(allocator, SizeAndAlign(8, 1), MemoryKind.static_mem);
	AllocationId heapId   = vm.memories[MemoryKind.heap_mem].allocate(allocator, SizeAndAlign(8, 1), MemoryKind.heap_mem);
	AllocationId stackId  = vm.memories[MemoryKind.stack_mem].allocate(allocator, SizeAndAlign(8, 1), MemoryKind.stack_mem);

	disasm(func.code[]);

	vm.pushRegisters(1);                              // 0: result register
	vm.pushRegister(VmRegister.makePtr(0, funcId));   // 1: argument function pointer
	vm.pushRegister(VmRegister.makePtr(0, staticId)); // 2: argument static pointer
	vm.pushRegister(VmRegister.makePtr(0, heapId));   // 3: argument heap pointer
	vm.pushRegister(VmRegister.makePtr(0, stackId));  // 4: argument stack pointer
	vm.call(funcId);
	vm.runVerbose();
	writefln("result %s", vm.getRegister(0));
}

struct VmState {
	@nogc nothrow:

	bool isRunning = true;
	bool isTrap; // must be checked on return

	u8 ptrSize; // 4 or 8
	u8 readWriteMask = MemFlags.heap_RW | MemFlags.stack_RW | MemFlags.static_RO;

	VoxAllocator* allocator;
	Memory[3] memories;

	Array!VmFunction functions;
	Array!VmFrame frames;
	Array!VmRegister registers;

	bool isReadableMemory(MemoryKind kind) {
		return cast(bool)(readWriteMask & (1 << kind));
	}

	bool isWritableMemory(MemoryKind kind) {
		return cast(bool)(readWriteMask & (1 << (kind + 4)));
	}

	AllocationId addFunction(VmFunction func) {
		u32 index = functions.length;
		functions.put(*allocator, func);
		u32 generation = 0;
		return AllocationId(index, generation, MemoryKind.func_id);
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
		if(funcId.kind != MemoryKind.func_id) panic("Invalid AllocationId kind, expected func_id, got %s", memoryKindString[funcId.kind]);
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
				if (src1.pointer.isDefined) {
					panic("add.i64 can only contain pointers in the first argument. (%s) Instr %s", *src1, frame.ip-3);
				}
				return;

			case const_s8:
				VmRegister* dst  = &registers[frame.firstRegister + frame.func.code[frame.ip++]];
				i8 src = frame.func.code[frame.ip++];
				dst.as_s64 = src;
				dst.pointer = AllocationId();
				return;

			case load_m8:
			case load_m16:
			case load_m32:
			case load_m64:
				u32 size = 1 << (op - load_m8);

				VmRegister* dst = &registers[frame.firstRegister + frame.func.code[frame.ip++]];
				VmRegister* src = &registers[frame.firstRegister + frame.func.code[frame.ip++]];

				if (src.pointer.isUndefined) panic("Reading from non-pointer value");
				if (!isReadableMemory(src.pointer.kind)) panic("Cannot read from %s", *src);

				Memory* mem = &memories[src.pointer.kind];
				Allocation* alloc = &mem.allocations[src.pointer.index];
				u8* memory = mem.memory[].ptr;

				u64 offset = src.as_u64;
				if (offset + size > alloc.size) {
					panic("Reading past the end of the allocation. Reading %s bytes at offset %s, from allocation of %s bytes", size, offset, alloc.size);
				}

				switch(op) {
					case load_m8:  dst.as_u64 = *cast( u8*)(memory + alloc.offset + offset); break;
					case load_m16: dst.as_u64 = *cast(u16*)(memory + alloc.offset + offset); break;
					case load_m32: dst.as_u64 = *cast(u32*)(memory + alloc.offset + offset); break;
					case load_m64: dst.as_u64 = *cast(u64*)(memory + alloc.offset + offset); break;
					default: assert(false);
				}

				if (ptrSize == size) {
					// this can be a pointer load
					dst.pointer = alloc.relocations.get(cast(u32)offset);
				} else {
					dst.pointer = AllocationId();
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
				if (!isWritableMemory(dst.pointer.kind)) panic("Cannot write to %s", *dst);

				Memory* mem = &memories[dst.pointer.kind];
				Allocation* alloc = &mem.allocations[dst.pointer.index];
				u8* memory = mem.memory[].ptr;

				u64 offset = dst.as_u64;
				if (offset + size > alloc.size) panic("Writing past the end of the allocation.");

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

	void printRegs() {
		write("     [");
		foreach(i, reg; registers) {
			if (i > 0) write(", ");
			write(reg);
		}
		writeln("]");
	}
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

struct VmFunction {
	@nogc nothrow:

	Array!u8 code;
	// result registers followed by argument registers
	u8 numCallerRegisters;
	u8 numLocalRegisters;
}

struct VmFrame {
	@nogc nothrow:

	VmFunction* func;
	u32 ip;
	// index of the first register
	u32 firstRegister;
}

struct SizeAndAlign {
	@nogc nothrow:

	u32 size;
	u32 alignment;
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
			sink.formattedWrite("%s%s+%s", memoryKindLetter[pointer.kind], pointer.index, as_u64);
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
	this(u32 index, u32 generation, MemoryKind kind) {
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
	//	MemoryKind,      "kind",  2,
	//));

	u32 generation() const {
		return cast(u32)(_generation & ((1 << 30) - 1));
	}

	// kind: heap, static, function, stack
	MemoryKind kind() const {
		return cast(MemoryKind)(_generation >> 30);
	}

	bool isDefined() const { return payload != 0; }
	bool isUndefined() const { return payload == 0; }
}

struct Allocation {
	u32 offset;
	u32 size;
	HashMap!(u32, AllocationId, u32.max) relocations;
}

struct Memory {
	@nogc nothrow:

	Array!Allocation allocations;
	Array!u8 memory;
	Array!u8 bitmap;
	u32 bytesUsed;

	AllocationId allocate(ref VoxAllocator allocator, SizeAndAlign sizeAlign, MemoryKind allocKind) {
		u32 index = allocations.length;
		u32 offset = bytesUsed;
		bytesUsed += sizeAlign.size;
		if (bytesUsed >= memory.length) panic("Out of %s memory", memoryKindString[allocKind]);
		memory.voidPut(allocator, sizeAlign.size);
		allocations.put(allocator, Allocation(offset, sizeAlign.size));
		u32 generation = 0;
		return AllocationId(index, generation, allocKind);
	}
}

enum MemoryKind : u8 {
	// heap must be 0, because we reserve 0th allocation and null pointer is a heap pointer with all zeroes
	heap_mem,
	stack_mem,
	static_mem,
	func_id,
}

immutable string[4] memoryKindString = [
	"heap",
	"stack",
	"static",
	"function",
];

immutable string[4] memoryKindLetter = [
	"h", "s", "g", "f"
];

// Low 4 bits are for reading, high 4 bits are for writing
// Bit position is eaual to MemoryKind
enum MemFlags : u8 {
	heap_RO   = 0b_0000_0001,
	stack_RO  = 0b_0000_0010,
	static_RO = 0b_0000_0100,
	heap_RW   = 0b_0001_0001,
	stack_RW  = 0b_0010_0010,
	static_RW = 0b_0100_0100,
}

// m - anything
// v - simd vectors
// f - float
// i - signed or unsigned int
// u - unsigned int
// s - signed int
// p - pointer

enum VmOpcode : u8 {
	ret,

	mov,

	add_i64,

	// sign-extended to i64
	const_s8,

	// zero-extended to u64
	load_m8,
	load_m16,
	load_m32,
	load_m64,

	store_m8,
	store_m16,
	store_m32,
	store_m64,
}
