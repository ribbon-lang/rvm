#!/bin/bash

zig build release -- x86_64-linux-gnu

sudo perf stat -d -r 10 ./zig-out/x86_64-linux-gnu-release-fast/ribboni
