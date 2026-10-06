#!/usr/bin/env bash
# 撮影 → 比較 → 検証を、フィクスチャの Storybook で通して確かめる。
#
# usage: bash test/vrt.test.sh [work-dir]
# Chrome は PATH にある google-chrome / chromium か、CHROME_BIN を使う。
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work="${1:-$(mktemp -d)}"
vrt() { node "$root/scripts/storybook-visual-regression.mjs" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# summary.json の Changed / New / Deleted / Passed が期待どおりかを見る。
expect_counts() {
  local report="$1" expected="$2" actual
  actual=$(node -e 'const s = require(process.argv[1]); console.log([s.changed, s.new, s.deleted, s.passed].join(" "))' "$report/summary.json")
  [ "$actual" = "$expected" ] || fail "$report: expected '$expected' (changed new deleted passed), got '$actual'"
  echo "ok: $(basename "$report") -> $actual"
}

rm -rf "$work"
mkdir -p "$work"
for variant in base changed added overflow; do
  node "$root/test/make-fixture.mjs" "$variant" "$work/sb-$variant"
done

vrt odiff-check

vrt capture --storybook-dir "$work/sb-base" --out "$work/baseline"
[ -f "$work/baseline/stories.json" ] || fail "capture did not write stories.json"

# 同じ Storybook を撮り直すと差分は出ない
vrt capture --storybook-dir "$work/sb-base" --out "$work/actual-same"
vrt compare --expected "$work/baseline" --actual "$work/actual-same" --out "$work/report-same" --report-version v1 \
  || fail "compare of identical screenshots exited non-zero"
expect_counts "$work/report-same" "0 0 0 3"
vrt verify --report "$work/report-same" --report-version v1

# 色を変えたストーリーは Changed になり、compare は非 0 で終わる
vrt capture --storybook-dir "$work/sb-changed" --out "$work/actual-changed"
if vrt compare --expected "$work/baseline" --actual "$work/actual-changed" --out "$work/report-changed" --report-version v1; then
  fail "compare with a changed story exited zero"
fi
expect_counts "$work/report-changed" "1 0 0 2"
vrt verify --report "$work/report-changed" --report-version v1
[ -f "$work/report-changed/diff/example-button--primary.png" ] || fail "diff image was not written"

# 足したストーリーは New。退行ではないので compare は 0 で終わる
vrt capture --storybook-dir "$work/sb-added" --out "$work/actual-added"
vrt compare --expected "$work/baseline" --actual "$work/actual-added" --out "$work/report-added" --report-version v1 \
  || fail "compare with only a new story exited non-zero"
expect_counts "$work/report-added" "0 1 0 3"

# ベースラインに無いものは Deleted(逆向きに比べる)
vrt compare --expected "$work/actual-added" --actual "$work/baseline" --out "$work/report-deleted" --report-version v1 \
  || fail "compare with only a deleted story exited non-zero"
expect_counts "$work/report-deleted" "0 0 1 3"

# ベースラインが無ければ全部 New
vrt compare --expected "$work/no-such-baseline" --actual "$work/baseline" --out "$work/report-empty" --report-version v1 \
  || fail "compare without a baseline exited non-zero"
expect_counts "$work/report-empty" "0 3 0 0"

# reportVersion が食い違うレポートは verify で落ちる
if vrt verify --report "$work/report-same" --report-version other 2>/dev/null; then
  fail "verify accepted a report of another revision"
fi
echo "ok: verify rejects another revision"

# 撮影範囲からはみ出すストーリーがあると撮影が落ちる
if vrt capture --storybook-dir "$work/sb-overflow" --out "$work/actual-overflow" 2>"$work/overflow.log"; then
  fail "capture accepted a story taller than the viewport"
fi
grep -Fq "example-list--tall" "$work/overflow.log" || fail "overflow error does not name the story"
echo "ok: capture rejects overflowing stories"

# allow-overflow なら警告だけで撮影は通る
vrt capture --storybook-dir "$work/sb-overflow" --out "$work/actual-overflow" --allow-overflow true
[ -f "$work/actual-overflow/example-list--tall.png" ] || fail "allow-overflow did not capture the tall story"
echo "ok: allow-overflow keeps capturing"

echo "all VRT script tests passed"
