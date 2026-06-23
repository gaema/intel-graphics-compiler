#!/bin/bash
# IGC source-build orchestration for the gaema local fork (DG2 spill fix +
# dpasw-emul), built against the LLVM-16 PRODUCTION component set.
#
# ROOT CAUSE (Xe2/Battlemage ICE):
#   Earlier from-source builds used off-version LLVM 17 (ocl-open-170 +
#   llvm_release_170). That toolchain compiles fine on DG2 but emits
#   "IGC: Internal Compiler Error: Invalid instruction" on Xe2/Battlemage.
#   IGC v2.34.0's documented PRODUCTION toolchain is LLVM 16 -- opencl-clang
#   ocl-open-160 + SPIRV-LLVM-Translator llvm_release_160. Rebuilding against
#   LLVM 16 makes the DG2 spill fix intact AND ICE-free on Xe2.
#
# This script therefore builds against the v2.34.0 PRODUCTION components:
#   - llvm-project          : llvmorg-16.0.6  (~/git/intel/llvm-16, worktree)
#   - opencl-clang          : ocl-open-160    (~/git/intel/opencl-clang-160, worktree)
#   - SPIRV-LLVM-Translator : llvm_release_160 (~/git/intel/SPIRV-LLVM-Translator-160, worktree)
#   - vc-intrinsics, SPIRV-Tools, SPIRV-Headers : master (shared)
#
# The 160 components are wired into ~/git/intel/llvm-16/llvm/projects/ as
# symlinks (opencl-clang, llvm-spirv, SPIRV-Headers, SPIRV-Tools), the layout
# the build expects (per documentation/build_ubuntu.md).
#
# BUILD-BLOCKER FIXES baked in (vs a vanilla v2.34.0 cmake invocation):
#   1. -DSPIRV_WERROR=OFF       : the bundled SPIRV-Tools builds with -Werror by
#                                 default and fails on warnings under this clang;
#                                 OFF lets it compile.
#   2. NO -DIGC_OPTION__BUILD_IGC_OPT=ON : the igc_opt directory is absent at
#                                 v2.34.0, so requesting it breaks configure.
#                                 (Dropped vs the earlier v2.36/2.37 invocation.)
#
# Deployed fleet-wide as libigc.so.2.34.9+0 / libigdfcl.so.2.34.9+0 plus the
# REQUIRED companion libopencl-clang.so.16 (libigdfcl dynamically links it).
#
# Usage: igc_build.sh [BUILD_DIR]
#   BUILD_DIR defaults to ~/local/build/igc-build-v234-llvm16 (host-local on
#   libre-computer).
#
# Produces libigc.so.2 + libigdfcl.so.2 in $OUTPUT_DIR (the companion
# libopencl-clang.so.16 is produced under the LLVM-16 build tree).
set -euo pipefail

IGC_SRC=/home/dxue/git/intel/intel-graphics-compiler
LLVM_SRC=/home/dxue/git/intel/llvm-16
SPIRV_HEADERS=/home/dxue/git/intel/SPIRV-Headers
BUILD_DIR="${1:-/home/dxue/local/build/igc-build-v234-llvm16}"
OUTPUT_DIR="$BUILD_DIR/IGC/Release"

echo "=== IGC build (LLVM-16 production toolchain) ==="
echo "  IGC src branch : $(cd "$IGC_SRC" && git rev-parse --short HEAD) ($(cd "$IGC_SRC" && git branch --show-current))"
echo "  build dir      : $BUILD_DIR"
echo "  output dir     : $OUTPUT_DIR"
echo "  LLVM           : $LLVM_SRC ($(cd "$LLVM_SRC" && git describe --tags 2>/dev/null || git rev-parse --short HEAD), Source mode)"
echo "  opencl-clang   : $(cd "$LLVM_SRC"/llvm/projects/opencl-clang && git rev-parse --short HEAD) ($(cd "$LLVM_SRC"/llvm/projects/opencl-clang && git branch --show-current 2>/dev/null || echo detached))"
echo "  llvm-spirv     : $(cd "$LLVM_SRC"/llvm/projects/llvm-spirv && git rev-parse --short HEAD) ($(cd "$LLVM_SRC"/llvm/projects/llvm-spirv && git branch --show-current 2>/dev/null || echo detached))"
echo "  started        : $(date)"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "=== cmake configure ==="
cmake -G Ninja "$IGC_SRC" \
  -DCMAKE_BUILD_TYPE=Release \
  -DSPIRV_WERROR=OFF \
  -DCMAKE_C_COMPILER=/usr/bin/clang \
  -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DIGC_OPTION__LLVM_MODE=Source \
  -DIGC_OPTION__LLVM_PREFERRED_VERSION=16.0.6 \
  -DIGC_OPTION__LLVM_SOURCES_DIR="$LLVM_SRC" \
  -DIGC_OPTION__LLVM_STOCK_SOURCES=OFF \
  -DIGC_OPTION__LINK_KHRONOS_SPIRV_TRANSLATOR=ON \
  -DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR="$SPIRV_HEADERS" \
  -DIGC_OPTION__API_ENABLE_OPAQUE_POINTERS=ON \
  -DIGC_OPTION__ENABLE_BF16_BIF=ON \
  -DIGC_OPTION__BIF_LINK_BC=ON \
  -DIGC_OPTION__COMPILE_LINK_ALLOW_UNSAFE_SIZE_OPT=ON \
  -DIGC_OPTION__IST_IGCC_ONLY=ON \
  -DIGC_OPTION__ENABLE_LIT_TESTS=OFF \
  -DIGC_OPTION__OUTPUT_DIR="$OUTPUT_DIR"

echo "=== ninja build ==="
ninja

echo "=== build done $(date) ==="
ls -la "$OUTPUT_DIR"/libigc.so* "$OUTPUT_DIR"/libigdfcl.so*
