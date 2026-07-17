#!/usr/bin/env bash
# Regression for the "pipe a big producer into grep -q under set -o pipefail"
# SIGPIPE false-fail (thor-arm64-deploy-pipeline.md, Step-2 bug, H00F 2026-07-11).
#
# WHAT IT PROVES
#   1. The OLD idiom  `big_producer | grep -q "$TAG" && present || absent`
#      under pipefail takes the WRONG (absent/die) branch even though the tag
#      IS present — because grep -q exits early, SIGPIPEs the producer, and
#      pipefail turns the 141 into the pipeline's exit code.
#   2. The FIXED idiom  `imgs="$(big_producer)"; [[ "$imgs" == *"$TAG"* ]]`
#      reports present correctly under the same conditions.
#   3. The fixed idiom still reports ABSENT for a genuinely missing tag
#      (no over-correction into blindness).
#
# No node needed — a synthetic producer models `k3s ctr images ls`. This is the
# bash control-flow proof; the end-to-end proof is a real run on Thor.
#
# Usage: bash sigpipe-pipefail-regression.sh   (exit 0 = all pass)
PASS=0; FAIL=0
ck(){ if [ "$2" = "$3" ]; then printf 'PASS  %s\n' "$1"; PASS=$((PASS+1))
  else printf 'FAIL  %s  expected[%s] got[%s]\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi; }

TAG="registry.sagecontinuum.org/beckman/yolo-object-counter:0.3.1"
# Target near the TOP of a long stream so grep -q matches early and SIGPIPEs
# the still-writing producer.
fake_ctr_ls(){ printf '%s\n' "$TAG   sha256:abc   10.7GiB"
  for i in $(seq 1 200000); do printf 'filler/image:%d s %d\n' "$i" "$i"; done; }

echo "-- 1. OLD idiom mis-reports ABSENT on a present tag (bug reproduced) --"
branch=$( set -o pipefail; fake_ctr_ls | grep -q "$TAG" 2>/dev/null \
            && echo PRESENT || echo ABSENT )
ck "old pipe idiom -> ABSENT despite present tag" "ABSENT" "$branch"

echo "-- 2. NEW idiom (capture then [[ == *tag* ]]) reports PRESENT --"
branch=$( set -o pipefail; imgs="$(fake_ctr_ls)"; \
          if [[ "$imgs" == *"$TAG"* ]]; then echo PRESENT; else echo ABSENT; fi )
ck "new idiom -> PRESENT" "PRESENT" "$branch"

echo "-- 3. NEW idiom still catches a genuinely missing tag --"
branch=$( set -o pipefail; imgs="other/image:1 s 1"; \
          if [[ "$imgs" == *"$TAG"* ]]; then echo PRESENT; else echo ABSENT; fi )
ck "new idiom -> ABSENT for real miss" "ABSENT" "$branch"

echo; echo "==== $PASS passed, $FAIL failed ===="; [ "$FAIL" -eq 0 ]
