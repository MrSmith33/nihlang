/// Copyright: Copyright (c) 2024 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.sys;

public import vox.lib.sys.entrypoint;
public import vox.lib.sys.stacktrace;

// arch
version(X86_64)      public import vox.lib.sys.arch.x64;
version(AArch64)     public import vox.lib.sys.arch.arm64;
version(WebAssembly) public import vox.lib.sys.arch.wasm;

// os
version(Windows) public import vox.lib.sys.os.windows;
version(Posix)   public import vox.lib.sys.os.posix;
version(linux)   public import vox.lib.sys.os.linux;
version(OSX)     public import vox.lib.sys.os.macos;
version(WASI)    public import vox.lib.sys.os.wasi;
else             public import vox.lib.sys.os.unknown;
