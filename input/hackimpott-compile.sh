#!/usr/bin/env bash
set -eux
rm -rf tmp
export glibc_install=/root/workdir/install
mkdir tmp
gcc \
  -L "${glibc_install}/lib" \
  -I "${glibc_install}/include" \
  -Wl,--rpath="${glibc_install}/lib" \
  -Wl,--dynamic-linker="${glibc_install}/lib/ld-linux-x86-64.so.2" \
  -std=c11 \
  -o a.out \
  -v \
  main.c

  #-static \
