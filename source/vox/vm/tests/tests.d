/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.tests.tests;

import vox.lib;
import vox.vm;
import vox.vm.tests.infra.test;

@nogc nothrow:

// Test[] vmTests() { return collectTests!(vox.vm.tests.tests)(); }

void testVM(ref VmTestContext c) {
	CodeBuilder b = CodeBuilder(c.vm.allocator);
	b.emit_store_ptr(c.vm.ptrSize, 2, 1);
	b.emit_store_ptr(c.vm.ptrSize, 3, 2);
	b.emit_store_ptr(c.vm.ptrSize, 4, 3);
	b.emit_load_ptr(c.vm.ptrSize, 0, 4);
	b.emit_ret();

	AllocId funcId   = c.vm.addFunction(b.code, 1, 4, 0);
	AllocId staticId = c.staticAlloc(SizeAndAlign(c.vm.ptrSize, 1));
	AllocId heapId   = c.heapAlloc(SizeAndAlign(c.vm.ptrSize, 1));
	AllocId stackId  = c.stackAlloc(SizeAndAlign(c.vm.ptrSize, 1));

	VmRegister[] res = c.call(stdoutSink, funcId, vmRegPtr(funcId), vmRegPtr(staticId), vmRegPtr(heapId), vmRegPtr(stackId));
	assert(res[0] == vmRegPtr(heapId));
}
