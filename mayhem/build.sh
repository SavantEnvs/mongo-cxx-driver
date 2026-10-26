#!/usr/bin/env bash
#
# mayhem/build.sh — builds (1) a sanitized, coverage-instrumented static bsoncxx/mongocxx + the fuzz
# harnesses and their -standalone reproducers, and (2) the upstream bsoncxx Catch2 suite and a
# known-answer probe with the project's NORMAL flags, which mayhem/test.sh runs.
#
# Air-gapped: mongo-c-driver (libbson/libmongoc) and Catch2 are baked into the image by the Dockerfile at
# /opt/toolchains/deps and handed to CMake's FetchContent as local sources.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

DEPS=/opt/toolchains/deps
cd "$SRC"

COMMON_CMAKE=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_VERSION=4.5.3
  -DBUILD_SHARED_LIBS=OFF
  -DFETCHCONTENT_FULLY_DISCONNECTED=ON
  -DFETCHCONTENT_SOURCE_DIR_MONGO-C-DRIVER="$DEPS/mongo-c-driver"
  -DFETCHCONTENT_SOURCE_DIR_EP_CATCH2="$DEPS/catch2"
)

# 1) Sanitized + SanCov-instrumented libraries. -fsanitize=fuzzer-no-link goes on the LIBRARY compile
#    (unconditionally) so the fuzzed code, not just the harness, reports coverage.
FUZZ_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
FB=cmake-build-mayhem
PREFIX="$SRC/$FB/prefix"
cmake -S . -B "$FB" "${COMMON_CMAKE[@]}" \
  -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build "$FB" -j"$MAYHEM_JOBS"
cmake --install "$FB" >/dev/null
rm -f "$SRC/mongocxx_install_manifest.txt"   # written into the source root by upstream's install rules

# 2) Harnesses: fuzzer binary + a run-once standalone reproducer each; LeakSanitizer is switched off at
#    build time by lsan_off.cc (leaks are not what this fleet fuzzes for).
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
PKG_CFLAGS=$(pkg-config --static --cflags libmongocxx1-static libbsoncxx1-static)
PKG_LIBS=$(pkg-config --static --libs libmongocxx1-static libbsoncxx1-static)
CXXSTD=-std=c++17

OBJ="$SRC/$FB/harness-obj"
mkdir -p "$OBJ"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$OBJ/lsan_off.o"

for h in fuzz_bson_document fuzz_bson_json fuzz_bson_types fuzz_uri; do
  $CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $PKG_CFLAGS -c "mayhem/$h.cpp" -o "$OBJ/$h.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OBJ/$h.o" "$OBJ/lsan_off.o" $PKG_LIBS -o "/mayhem/$h"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$OBJ/$h.o" "$OBJ/standalone_main.o" "$OBJ/lsan_off.o" $PKG_LIBS -o "/mayhem/$h-standalone"
done

# 3) The upstream bsoncxx suite (Catch2) with the project's normal flags — no sanitizers, no DWARF pin —
#    plus the known-answer probe, linked against the same normal-flag libraries.
TB=cmake-build-mayhem-tests
cmake -S . -B "$TB" "${COMMON_CMAKE[@]}" -DENABLE_TESTS=ON \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build "$TB" -j"$MAYHEM_JOBS" --target test_bson bsoncxx_static
BSONC_A=$(find "$TB/_deps/mongo-c-driver-build" -name 'libbson2.a' | head -n1)
$CXX $CXXSTD -O1 $COVERAGE_FLAGS $PKG_CFLAGS mayhem/kat.cpp "$TB/src/bsoncxx/libbsoncxx1-static.a" "$BSONC_A" -lrt -o "$TB/kat"
