#!/usr/bin/env bash
# PR に承認ラベルが付いているかを API で引いて、付いていれば 0 で終わる。
#
# event の payload(`github.event.pull_request.labels`)は実行開始時点のスナップショットなので、
# 撮影中に付けた承認を拾えない。今の状態で判定するために毎回 API を引く。
#
# env: GH_TOKEN / PR_NUMBER / APPROVAL_LABEL
set -euo pipefail

: "${PR_NUMBER:?}" "${APPROVAL_LABEL:?}"
# grep -q へ直接パイプすると、一致した時点で grep が抜けて gh が SIGPIPE で落ち、
# pipefail のせいで「付いていない」と判定されることがある。一度受けてから探す。
labels=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/labels" --jq '.[].name')
printf '%s\n' "$labels" | grep -Fxq -- "$APPROVAL_LABEL"
