#!/usr/bin/env bash
# PR に VRT の結果を 1 件だけのコメント(sticky)として書く。既にあれば上書きする。
#
# env:
#   GH_TOKEN / PR_NUMBER / APPROVAL_LABEL
#   SUMMARY          summary.json のパス(無いこともある)
#   REPORT_URL       公開したレポートの URL
#   RUN_URL          この run の URL
#   STORYBOOK_URL    任意。Storybook プレビューの URL
#   COMMENT_MARKER   sticky コメントを見分ける目印(HTML コメント)
#   COMMENT_TITLE    見出し
#   CAPTURE_OUTCOME / COMPARE_OUTCOME / VERIFY_OUTCOME / PUBLISH_OUTCOME / WAIT_OUTCOME 各段の結果
set -euo pipefail

: "${PR_NUMBER:?}" "${APPROVAL_LABEL:?}" "${COMMENT_MARKER:?}" "${COMMENT_TITLE:?}"
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
body_file="${RUNNER_TEMP:-/tmp}/storybook-vrt-comment.md"

{
  echo "$COMMENT_MARKER"
  echo "## $COMMENT_TITLE"
  echo ""
} > "$body_file"

# 配信の確認まで通って初めてリンクが開ける。待たない設定(WAIT_OUTCOME が skipped)なら
# push できた時点で公開できたとみなす。
published=false
if [ "${PUBLISH_OUTCOME:-}" = "success" ] && [ "${WAIT_OUTCOME:-skipped}" != "failure" ]; then
  published=true
fi

if [ "$published" = "true" ] && [ -f "${SUMMARY:-}" ]; then
  read -r changed added deleted passed < <(node -e 'const s = require(process.argv[1]); console.log(s.changed, s.new, s.deleted, s.passed)' "$SUMMARY")
  # 差分がある間はチェックが赤になる。赤を見た人が次に何をすればよいか
  # (レポートを見て、意図した変更ならラベルを付ける)をここに書いておく。
  if [ "$changed" -gt 0 ]; then
    if bash "$script_dir/has-approval-label.sh"; then
      headline="差分がありますが、\`${APPROVAL_LABEL}\` ラベルで承認済みのためチェックは通しています。"
    else
      headline="差分が見つかりました。レポートで確認し、意図した変更なら \`${APPROVAL_LABEL}\` ラベルを付けてください（付けるとチェックが通ります）。意図しない変更ならコードを直してください。"
    fi
  else
    headline="差分はありませんでした。"
  fi
  {
    echo "$headline"
    echo ""
    # 玉の色はレポート画面の分類アイコンと揃えてある。
    echo "| 🔴 Changed | ⚪ New | ⚫ Deleted | 🔵 Passed |"
    echo "| ---: | ---: | ---: | ---: |"
    echo "| $changed | $added | $deleted | $passed |"
    echo ""
    echo "- [VRT report](${REPORT_URL})"
  } >> "$body_file"
else
  {
    if [ -f "${SUMMARY:-}" ]; then
      echo "レポートを公開できませんでした。"
    elif [ "${CAPTURE_OUTCOME:-}" = "failure" ]; then
      echo "撮影に失敗しました。ストーリーが撮影範囲に収まっていない場合は、どのストーリーが何 px かを Actions の要約に書いています。"
    else
      echo "レポートが見つかりませんでした。"
    fi
    echo ""
    # 括弧内は action の各段の名前なので英語のままにする。
    echo "- レポート未更新（capture: ${CAPTURE_OUTCOME:-skipped} / compare: ${COMPARE_OUTCOME:-skipped} / verify: ${VERIFY_OUTCOME:-skipped} / publish: ${PUBLISH_OUTCOME:-skipped} / wait: ${WAIT_OUTCOME:-skipped}）"
  } >> "$body_file"
fi

echo "- [Actions](${RUN_URL})" >> "$body_file"
if [ -n "${STORYBOOK_URL:-}" ]; then
  echo "- [Storybook](${STORYBOOK_URL})" >> "$body_file"
fi

# コメントが 30 件を超える PR でも目印のコメントを見つけられるよう、全ページを引く。
marked_ids=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
  --jq '.[] | select(.body | startswith(env.COMMENT_MARKER)) | .id')
comment_id=$(printf '%s\n' "$marked_ids" | head -n 1)
if [ -n "$comment_id" ]; then
  gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${comment_id}" --field body=@"$body_file" > /dev/null
else
  gh api -X POST "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" --field body=@"$body_file" > /dev/null
fi
echo "commented on #${PR_NUMBER}"
