/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm;

import vox.lib;

@nogc nothrow:


void testVM() {
	enum static_bytes = 64*1024;
	enum heap_bytes = 64*1024;
	enum stack_bytes = 64*1024;
	enum PTR_SIZE = 4;
	VoxAllocator allocator;

	VmOpcode load_op = PTR_SIZE == 4 ? VmOpcode.load_m32 : VmOpcode.load_m64;
	VmOpcode store_op = PTR_SIZE == 4 ? VmOpcode.store_m32 : VmOpcode.store_m64;

	CodeBuilder b = CodeBuilder(&allocator);
	b.emit_binop(store_op, 2, 1);
	b.emit_binop(store_op, 3, 2);
	b.emit_binop(store_op, 4, 3);
	b.emit_binop(load_op, 0, 4);
	b.emit_ret();

	VmFunction func = {
		code : b.code,
		numCallerRegisters : 2,
		numLocalRegisters : 0,
	};

	VmState vm = {
		allocator : &allocator,
		readWriteMask : MemFlags.heap_RW | MemFlags.stack_RW | MemFlags.static_RW,
		ptrSize : PTR_SIZE,
	};

	vm.reserveMemory(static_bytes, heap_bytes, stack_bytes);

	AllocationId funcId   = vm.addFunction(func);
	AllocationId staticId = vm.memories[MemoryKind.static_mem].allocate(allocator, SizeAndAlign(PTR_SIZE, 1), MemoryKind.static_mem);
	AllocationId heapId   = vm.memories[MemoryKind.heap_mem].allocate(allocator, SizeAndAlign(PTR_SIZE, 1), MemoryKind.heap_mem);
	AllocationId stackId  = vm.memories[MemoryKind.stack_mem].allocate(allocator, SizeAndAlign(PTR_SIZE, 1), MemoryKind.stack_mem);

	// disasm(stdoutSink, func.code[]);

	vm.pushRegisters(1);                              // 0: result register
	vm.pushRegister(VmRegister.makePtr(0, funcId));   // 1: argument function pointer
	vm.pushRegister(VmRegister.makePtr(0, staticId)); // 2: argument static pointer
	vm.pushRegister(VmRegister.makePtr(0, heapId));   // 3: argument heap pointer
	vm.pushRegister(VmRegister.makePtr(0, stackId));  // 4: argument stack pointer
	vm.call(funcId);
	vm.runVerbose(stdoutSink);
	writefln("result %s", vm.getRegister(0));
}

struct VmState {
	@nogc nothrow:

	// 4 or 8
	u8 ptrSize;
	u8 readWriteMask = MemFlags.heap_RW | MemFlags.stack_RW | MemFlags.static_RO;

	bool isRunning = true;

	// must be checked on return
	VmStatus status;
	VmError error;

	VoxAllocator* allocator;
	Memory[3] memories;

	Array!VmFunction functions;
	Array!VmFrame frames;
	Array!VmRegister registers;

	void reserveMemory(u32 static_bytes, u32 heap_bytes, u32 stack_bytes) {
		memories[MemoryKind.static_mem].reserve(*allocator, static_bytes, ptrSize);
		memories[MemoryKind.heap_mem].reserve(*allocator, heap_bytes, ptrSize);
		memories[MemoryKind.stack_mem].reserve(*allocator, stack_bytes, ptrSize);
		// skip one allocation for null pointer
		memories[MemoryKind.heap_mem].allocations.voidPut(*allocator, 1);
	}

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

	void run(scope SinkDelegate sink) {
		isRunning = true;
		status = VmStatus.OK;

		while(isRunning) step();

		if (status != VmStatus.OK) {
			u32 ipCopy = error.ip;
			disasmOne(sink, frames.back.func.code[], ipCopy);
			sink("Error: ");
			format_vm_error(sink);
		}
	}

	void runVerbose(scope SinkDelegate sink) {
		isRunning = true;
		status = VmStatus.OK;

		writeln("---");
		printRegs();
		while(isRunning) {
			u32 ipCopy = frames.back.ip;
			disasmOne(sink, frames.back.func.code[], ipCopy);
			step();
			if (status != VmStatus.OK) {
				sink("Error: ");
				format_vm_error(sink);
				break;
			}
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

				if (frames.length == 0) {
					isRunning = false;
				}
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
				if (src1.pointer.isDefined) return setTrap(VmStatus.ERR_PTR_PLUS_PTR, frame.ip-4);
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

				if (src.pointer.isUndefined) return setTrap(VmStatus.ERR_LOAD_NOT_PTR, frame.ip-3);
				if (!isReadableMemory(src.pointer.kind)) panic("Cannot read from %s", *src);

				Memory* mem = &memories[src.pointer.kind];
				Allocation* alloc = &mem.allocations[src.pointer.index];
				u8* memory = mem.memory[].ptr;

				u64 offset = src.as_u64;
				if (offset + size > alloc.size) return setTrap(VmStatus.ERR_LOAD_OOB, frame.ip-3);

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
				if (!isWritableMemory(dst.pointer.kind)) return setTrap(VmStatus.ERR_STORE_TO_RO, frame.ip-3);

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

	private void setTrap(VmStatus status, u32 ip) {
		isRunning = false;
		this.status = status;
		error.ip = ip;
	}

	void printRegs() {
		write("     [");
		foreach(i, reg; registers) {
			if (i > 0) write(", ");
			write(reg);
		}
		writeln("]");
	}

	void format_vm_error(scope SinkDelegate sink) {
		if (status == VmStatus.OK) return;

		VmFrame* frame = &frames.back();
		u8[] code = frame.func.code[];
		u32 firstReg = frame.firstRegister;

		final switch(status) with(VmStatus) {
			case OK:
				sink("ok");
				break;

			case ERR_PTR_PLUS_PTR:
				VmRegister* dst  = &registers[firstReg + code[error.ip+1]];
				VmRegister* src0 = &registers[firstReg + code[error.ip+2]];
				VmRegister* src1 = &registers[firstReg + code[error.ip+3]];

				sink.formattedWrite("add.i64 can only contain pointers in the first argument.\n  r%s: %s\n  r%s: %s\n  r%s: %s\n",
					code[error.ip+1], *dst,
					code[error.ip+2], *src0,
					code[error.ip+3], *src1);
				break;

			case ERR_STORE_TO_RO:
				VmRegister* dst = &registers[firstReg + code[error.ip+1]];
				VmRegister* src = &registers[firstReg + code[error.ip+2]];

				sink.formattedWrite("Cannot store to read-only memory.\n  r%s: %s\n  r%s: %s\n",
					code[error.ip+1], *dst,
					code[error.ip+2], *src);
				break;

			case ERR_LOAD_NOT_PTR:
				VmRegister* src = &registers[firstReg + code[error.ip+2]];
				sink.formattedWrite("Reading from non-pointer value (r%s:%s)", code[error.ip+2], *src);
				break;

			case ERR_LOAD_OOB:
				u8 op = code[error.ip+0];
				u32 size = 1 << (op - VmOpcode.load_m8);
				VmRegister* src = &registers[firstReg + code[error.ip+2]];
				Memory* mem = &memories[src.pointer.kind];
				Allocation* alloc = &mem.allocations[src.pointer.index];

				u64 offset = src.as_u64;

				sink.formattedWrite("Reading past the end of the allocation (r%s:%s).\nReading %s bytes at offset %s, from allocation of %s bytes\n",
					code[error.ip+2], *src,
					size,
					offset,
					alloc.size);
				break;
		}
	}
}

enum VmStatus : u8 {
	OK,
	ERR_PTR_PLUS_PTR,
	ERR_STORE_TO_RO,
	ERR_LOAD_NOT_PTR,
	ERR_LOAD_OOB,
}

struct VmError {
	u32 ip; // start of instruction in a function
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

	void emit_binop(VmOpcode op, u8 dst, u8 src) {
		code.put(*allocator, op);
		code.put(*allocator, dst);
		code.put(*allocator, src);
	}
}

void disasm(scope SinkDelegate sink, u8[] code, u32 offset = 0) {
	u32 ip;
	while(ip < code.length) {
		disasmOne(sink, code, ip, offset);
	}
}

void disasmOne(scope SinkDelegate sink, u8[] code, ref u32 ip, u32 offset = 0) {
	auto addr = ip + offset;
	VmOpcode op = cast(VmOpcode)code[ip++];
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

	// ptrSize is 4 or 8
	void reserve(ref VoxAllocator allocator, u32 size, u32 ptrSize) {
		assert(ptrSize == 4 || ptrSize == 8, "Invalid ptr size");
		memory.voidPut(allocator, size);
		// 1 bit per pointer slot
		// pointers must be aligned in memory
		// each allocation is aligned at least to a pointer size
		bitmap.voidPut(allocator, size / (ptrSize * 8));
	}

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
