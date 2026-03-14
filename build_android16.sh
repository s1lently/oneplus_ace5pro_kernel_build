#!/usr/bin/env bash
# build_android16.sh — OnePlus Ace 5 Pro, Android 16 (OxygenOS 16), kernel 6.6.89
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/build_common.sh"
BRANCH="oneplus/sm8750_b_16.0.0_oneplus_ace5_pro"
LOCALVERSION="-android15-8-o-4k"
do_build
