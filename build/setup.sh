#!/bin/bash
set -euo pipefail

ldc2 -wi -m64 -O3 -g -d-debug --link-internally builder.d