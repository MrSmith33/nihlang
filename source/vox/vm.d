/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm;

import vox.lib;

@nogc nothrow:


void testVM() {
	VoxAllocator allocator;

	Array!u8 code;
	code.put(allocator, VmOpcode.mov);
	code.put(allocator, 0);
	code.put(allocator, 1);
	code.put(allocator, VmOpcode.ret);

	VmFunction func = {
		code : code,
		numCallerRegisters : 2,
		numLocalRegisters : 0,
	};

	VmState vm = {
		allocator : &allocator,
	};

	AllocationId funcId = vm.addFunction(func);

	//disasm(code[]);

	vm.pushRegisters(1); // result register
	vm.pushRegister_u64(42); // argument
	vm.call(funcId);
	vm.runVerbose();
	writefln("result %s", vm.getRegister(0).as_u64);
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
	VoxAllocator* allocator;
	Array!VmFunction functions;
	Array!VmFrame frames;
	Array!Register registers;
	u8 ptrSize; // 4 or 8

	AllocationId addFunction(VmFunction func) {
		u32 index = functions.length;
		functions.put(*allocator, func);
		u32 generation = 0;
		return AllocationId(index, generation, AllocationKind.func_id);
	}

	void pushRegisters(u32 numRegisters) {
		registers.voidPut(*allocator, numRegisters);
	}

	void pushRegister_u64(u64 val) {
		registers.put(*allocator, Register(val));
	}

	Register getRegister(u32 index) {
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
		while(frames.length) step();
	}

	void runVerbose() {
		writeln("---");
		printRegs();
		while(frames.length) {
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
				return;
			case mov:
				u32 dst = frame.func.code[frame.ip++];
				u32 src = frame.func.code[frame.ip++];
				registers[frame.firstRegister + dst] = registers[frame.firstRegister + src];
				return;
		}
	}

	void printRegs() {
		write("     [");
		foreach(i, reg; registers) {
			if (i > 0) write(", ");
			write("r", i, " ");
			printReg(reg);
		}
		writeln("]");
	}

	void printReg(Register reg) {
		write(reg.as_u64);
	}
}

// Register can contain 0 or 1 pointer, so instead of storing a hashmap of relocations
// we store a single AllocationId
// vector registers are forbidden to store pointers
align(16)
struct Register {
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
}

//import std.bitmanip : bitfields;
struct AllocationId {
	@nogc nothrow:
	this(u32 index, u32 generation, AllocationKind kind) {
		this.index = index;
		this._generation = (generation & ((1 << 30) - 1)) | (kind << 30);
	}

	u32 index;
	private u32 _generation;
	//mixin(bitfields!(
	//	u32,           "generation", 30,
	//	AllocationKind,      "kind",  2,
	//));

	u32 generation() {
		return cast(u32)(_generation & ((1 << 30) - 1));
	}

	// kind: heap, static, function, stack
	AllocationKind kind() {
		return cast(AllocationKind)(_generation >> 30);
	}

	bool isDefined() { return index != 0; }
	bool isUndefined() { return index == 0; }
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
			u32 dst = code[ip++];
			u32 src = code[ip++];
			writefln("%04x mov r%s, r%s", addr, dst, src);
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
}

