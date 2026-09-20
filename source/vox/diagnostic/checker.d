/// Copyright: Copyright (c) 2026 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
///
module vox.diagnostic.checker;

import vox.context;
import vox.lib;

struct DiagnosticChecker {
	@nogc nothrow:

	// Last command
	enum State {
		init,
		diag,
		anno,
	}

	VoxContext* context;
	SinkDelegate sink;
	Diagnostic* diag;
	State state;
	u32 selectedAnnotation;

	DiagnosticChecker expectDiagnostic(string msg = null, string file = __FILE__, int line = __LINE__) {
		if (state != State.init) {
			panic(line, file, 0, "expectDiagnostic must be the first call in a chain");
		}
		if (msg is null) return DiagnosticChecker(context, sink, diag, State.diag);
		if (msg == diag.msg) return DiagnosticChecker(context, sink, diag, State.diag);

		panic(line, file, 0, "Unexpected error message:\n  Expected: %s\n  Got: %s\n", msg, diag.msg);

		return this;
	}

	DiagnosticChecker withAnnotation(string msg = null, string file = __FILE__, int line = __LINE__) {
		if (state != State.diag && state != State.anno) {
			panic(line, file, 0, "expectDiagnostic must be the first call in a chain");
		}

		if (msg is null && diag.annotations.length == 1) {
			// Select annotation zero
			return DiagnosticChecker(context, sink, diag, State.anno, 0);
		}

		if (msg is null) {
			panic(line, file, 0, "Diagnostic has multiple annotations, but message was not specified in a call to withAnnotation");
		}

		foreach(i, ref a; diag.annotations) {
			if (a.msg == msg) {
				return DiagnosticChecker(context, sink, diag, State.anno, cast(u32)i);
			}
		}

		panic(line, file, 0, "Cannot find annotation with message: %s\n", msg);
	}

	DiagnosticChecker pointingAt(string at, string file = __FILE__, int line = __LINE__) {
		if (state != State.anno) {
			panic(line, file, 0, "pointingAt must be called immediately after withAnnotation");
		}

		auto data = context.bufs.sources.data;
		auto loc = diag.annotations[selectedAnnotation].location;
		auto slice = data[loc.start.offset..loc.end.offset];

		if (at == slice) return this;

		sink.formattedWrite("Annotation is pointing at the wrong location:\n  Expected: %s\n  Got: %s\n", at, slice);
		return this;
	}
}
