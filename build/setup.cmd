@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

ldc2 -wi -m64 -O3 -g -d-debug --link-internally -verror-style=gnu builder.d