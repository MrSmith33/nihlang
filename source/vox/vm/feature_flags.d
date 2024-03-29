/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.vm.feature_flags;

enum OUT_REFS_PER_ALLOCATION = false;
enum OUT_REFS_PER_MEMORY = !OUT_REFS_PER_ALLOCATION;

// Checks for invariants
enum FAST_CHECKS = true;
// ditto, but slow
enum SLOW_CHECKS = false;
// Detect reading from uninitialized memory
enum SANITIZE_UNINITIALIZED_MEM = true;
// Detect existance of pointers to heap or stack memory that was freed
enum SANITIZE_DANGLING_PTR = true;
// Detect when heap allocation loses last pointer and is not freed
enum SANITIZE_MEM_LEAK = true;
// Initializes all newly pushed registers
enum INIT_REGISTERS = false;
