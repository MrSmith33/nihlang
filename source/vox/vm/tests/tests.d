/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.tests.tests;

import vox.lib;
import vox.vm.vm;
import vox.vm.tests.infra.test;

@nogc nothrow:

// Test[] vmTests() { return collectTests!(vox.vm.tests.tests)(); }

void testVM(ref VmTestContext c) {
	VmOpcode load_op = c.vm.ptrSize == 4 ? VmOpcode.load_m32 : VmOpcode.load_m64;
	VmOpcode store_op = c.vm.ptrSize == 4 ? VmOpcode.store_m32 : VmOpcode.store_m64;

	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_binop(store_op, 2, 1);
	b.emit_binop(store_op, 3, 2);
	b.emit_binop(store_op, 4, 3);
	b.emit_binop(load_op, 0, 4);
	b.emit_ret();

	AllocationId funcId   = c.vm.addFunction(b.code, 1, 4, 0);
	AllocationId staticId = c.staticAlloc(SizeAndAlign(c.vm.ptrSize, 1));
	AllocationId heapId   = c.heapAlloc(SizeAndAlign(c.vm.ptrSize, 1));
	AllocationId stackId  = c.stackAlloc(SizeAndAlign(c.vm.ptrSize, 1));

	// disasm(stdoutSink, b.code[]);

	VmRegister[] res = c.call(stdoutSink, funcId, vmRegPtr(funcId), vmRegPtr(staticId), vmRegPtr(heapId), vmRegPtr(stackId));
	writefln("result %s", res[0]);
}
