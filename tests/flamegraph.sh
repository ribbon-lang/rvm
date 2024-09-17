#!/bin/bash

sudo perf record -F 9000 -a -g -- ./zig-out/x86_64-linux-gnu-release-fast/ribboni
sudo perf script > out.perf
stackcollapse-perf out.perf > out.folded
flamegraph out.folded > ribboni.svg

rm -f perf.data
rm out.perf
rm out.folded
