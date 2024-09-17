#!/bin/bash

sudo perf stat -d -r 10 ./zig-out/x86_64-linux-gnu-release-fast/ribboni
