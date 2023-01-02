/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib;

public import vox.lib.algo;
public import vox.lib.error;
public import vox.lib.format;
public import vox.lib.hash;
public import vox.lib.io;
public import vox.lib.log;
public import vox.lib.math;
public import vox.lib.string;
public import vox.lib.types;

public import vox.lib.system.entrypoint;
public import vox.lib.system.stacktrace;

     version(Windows)     public import vox.lib.system.windows;
else version(linux)       public import vox.lib.system.linux;
else version(OSX)         public import vox.lib.system.macos;
// WASI must be checked before WebAssembly, because WASI is defined together with WebAssembly
else version(WASI)        public import vox.lib.system.wasi;
else version(WebAssembly) public import vox.lib.system.wasm;
