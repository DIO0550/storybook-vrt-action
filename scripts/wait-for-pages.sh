#!/usr/bin/env bash
# 公開した summary.json が GitHub Pages から実際に配信されるまで待つ。
#
# push の有無で分岐させず、再実行などで push すべき差分が無かったときも配信を確かめる
# (見えていないのに緑になる状態を作らない)。
#
# env:
#   SUMMARY_URL    配信先の summary.json の URL
#   REPORT_VERSION summary.json の reportVersion がこの値になるまで待つ
#   WAIT_SECONDS   1 回の待ちの上限(秒)
#   GH_TOKEN       Pages のビルド要求に使う(pages: write が無ければ要求は失敗するが待ちは続ける)
set -euo pipefail

: "${SUMMARY_URL:?}" "${REPORT_VERSION:?}" "${WAIT_SECONDS:?}"
downloaded="${RUNNER_TEMP:-/tmp}/storybook-vrt-published-summary.json"

wait_for_publication() {
  local attempts=$(((WAIT_SECONDS + 4) / 5))
  for attempt in $(seq 1 "$attempts"); do
    if curl --fail --silent --show-error --location "$SUMMARY_URL" -o "$downloaded" \
      && DOWNLOADED="$downloaded" node -e 'const summary = require(process.env.DOWNLOADED); if (summary.reportVersion !== process.env.REPORT_VERSION) process.exit(1)'; then
      echo "report revision $REPORT_VERSION is published"
      return 0
    fi
    echo "Waiting for Pages report revision $REPORT_VERSION (attempt $attempt/$attempts)..."
    sleep 5
  done
  return 1
}

# 通常は push が起こしたビルドで配信される。ここで先に `POST /pages/builds` を足すと
# 1 コミットにつきデプロイが 2 本になり、同時に 1 つしか走れない Pages でキューが詰まる。
# ただし短い間隔で 2 回 push すると、後の push のツリーがデプロイされないまま終わることがあり、
# そこからは自力で復帰できない。配信されていないときに限りビルドを 1 本だけ要求する。
if wait_for_publication; then
  exit 0
fi
echo "revision is still not published; requesting a Pages build"
# 既にビルド中(409)なら要求は通らないが、待つこと自体は正しいので続ける
gh api --method POST "repos/${GITHUB_REPOSITORY}/pages/builds" \
  || echo "build request was rejected; waiting for the running build instead"
if wait_for_publication; then
  exit 0
fi
echo "::error::report revision $REPORT_VERSION was not published at $SUMMARY_URL"
exit 1
