#!/bin/bash

valgrind --tool=cachegrind --cache-sim=yes --branch-sim=yes ./zig-out/x86_64-linux-gnu-release-fast/ribboni
