#!/bin/bash
# Раннер конвертации B1 (uupdump convert.sh v0.7.3) — песочница без root
cd /home/z/my-project/b1/work || exit 1
export LD_LIBRARY_PATH=/home/z/my-project/b1/tools/prefix/usr/lib/x86_64-linux-gnu
export PATH=/home/z/my-project/b1/tools/prefix/usr/bin:/home/z/my-project/b1/tools/prefix/usr/sbin:$PATH
export HOME=/home/z
exec ./convert.sh
