#!/bin/bash
set -euo pipefail
cd "${0%/*}"

ldc2 -wi -m64 -O3 -g -d-debug --link-internally builder.d