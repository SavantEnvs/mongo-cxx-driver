#!/usr/bin/env bash
#
# mayhem/test.sh — RUN bsoncxx's own Catch2 suite plus known-answer probes (both built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TB="$SRC/cmake-build-mayhem-tests"
TEST_BSON="$TB/src/bsoncxx/test/test_bson"
KAT="$TB/kat"
for f in "$TEST_BSON" "$KAT"; do
  [ -x "$f" ] || { echo "FATAL: $f missing — mayhem/build.sh should have built it" >&2; exit 2; }
done

passed=0; failed=0; skipped=0

# 1) Upstream bsoncxx suite (Catch2, no server needed). Parse its own summary line: a neutered
#    binary prints nothing, so nothing matches and the suite is counted as a failure.
out=$("$TEST_BSON" --reporter compact 2>&1); rc=$?
echo "$out" | tail -n 5
if line=$(echo "$out" | grep -E '^test cases: +[0-9]+ \|'); then
  tc=$(echo "$line" | sed -E 's/^test cases: +([0-9]+) \|.*/\1/')
  p=$(echo "$line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo 0)
  f=$(echo "$line" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo 0)
  s=$(echo "$line" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+' || echo 0)
  : "${p:=0}" "${f:=0}" "${s:=0}"
  [ "$tc" -ge 250 ] || { echo "FAIL: only $tc Catch2 test cases ran (expected ~271)"; f=$((f + 1)); }
  passed=$((passed + p)); failed=$((failed + f)); skipped=$((skipped + s))
elif m=$(echo "$out" | grep -oE 'Passed all [0-9]+ test cases' | grep -oE '[0-9]+'); then
  passed=$((passed + m))
else
  echo "FAIL: no Catch2 summary line from test_bson (rc=$rc)"; failed=$((failed + 1))
fi
[ "$rc" -eq 0 ] || { echo "FAIL: test_bson exited $rc"; failed=$((failed + 1)); }

# 2) Known-answer probes through the dynamically linked kat binary: fixed Extended JSON in -> exact
#    BSON length / element count / canonical + relaxed JSON out.
kat_check() {
  local name="$1" input="$2" expected="$3" got
  got=$("$KAT" "$input" 2>&1) || got="(kat exited $?) $got"
  if [ "$got" == "$expected" ]; then passed=$((passed + 1)); echo "ok   kat: $name"
  else failed=$((failed + 1)); echo "FAIL kat: $name"; echo "--- expected"; echo "$expected"; echo "--- got"; echo "$got"; fi
}

kat_check empty '{}' 'length=5
elements=0
valid=1
canonical={ }
relaxed={ }'

kat_check date_array '{"a":{"$date":{"$numberLong":"0"}},"x":[true,null,2.5]}' 'length=42
elements=2
valid=1
canonical={ "a" : { "$date" : { "$numberLong" : "0" } }, "x" : [ true, null, { "$numberDouble" : "2.5" } ] }
relaxed={ "a" : { "$date" : "1970-01-01T00:00:00Z" }, "x" : [ true, null, 2.5 ] }'

kat_check decimal_oid_binary '{"d":{"$numberDecimal":"1.5"},"o":{"$oid":"507f1f77bcf86cd799439011"},"b":{"$binary":{"base64":"AQID","subType":"00"}}}' 'length=50
elements=3
valid=1
canonical={ "d" : { "$numberDecimal" : "1.5" }, "o" : { "$oid" : "507f1f77bcf86cd799439011" }, "b" : { "$binary" : { "base64" : "AQID", "subType" : "00" } } }
relaxed={ "d" : { "$numberDecimal" : "1.5" }, "o" : { "$oid" : "507f1f77bcf86cd799439011" }, "b" : { "$binary" : { "base64" : "AQID", "subType" : "00" } } }'

kat_check ints_string '{"i":7,"l":{"$numberLong":"5000000000"},"s":"hi"}' 'length=33
elements=3
valid=1
canonical={ "i" : { "$numberInt" : "7" }, "l" : { "$numberLong" : "5000000000" }, "s" : "hi" }
relaxed={ "i" : 7, "l" : 5000000000, "s" : "hi" }'

# A malformed document must be refused, not silently accepted.
got=$("$KAT" '{"a":' 2>&1); krc=$?
if [ "$krc" -eq 3 ] && [[ "$got" == error=* ]]; then passed=$((passed + 1)); echo "ok   kat: malformed JSON rejected"
else failed=$((failed + 1)); echo "FAIL kat: malformed JSON: rc=$krc out=$got"; fi

emit_ctrf "catch2+kat" "$passed" "$failed" "$skipped"
