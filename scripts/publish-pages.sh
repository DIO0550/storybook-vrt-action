#!/usr/bin/env bash
# Pages 用ブランチの 1 つのパスを置き換えて push する(SOURCE_DIR が空ならそのパスを消す)。
#
# env:
#   PAGES_BRANCH   公開先ブランチ(無ければ空の orphan として作る)
#   TARGET_PATH    ブランチ内のパス(ここだけを置き換え、他のパスには触れない)
#   SOURCE_DIR     置く中身のディレクトリ。空ならパスを削除する
#   COMMIT_MESSAGE コミットメッセージ
#   WORKTREE_DIR   作業用 worktree を作る場所
#   REPORT_VERSION 任意。指定すると、置いた summary.json の reportVersion が一致することを確かめる
set -euo pipefail

: "${PAGES_BRANCH:?}" "${TARGET_PATH:?}" "${COMMIT_MESSAGE:?}" "${WORKTREE_DIR:?}"
SOURCE_DIR="${SOURCE_DIR:-}"
REPORT_VERSION="${REPORT_VERSION:-}"

case "$TARGET_PATH" in
  /* | *..* | . | "")
    echo "::error::invalid target path for $PAGES_BRANCH: '$TARGET_PATH'"
    exit 1
    ;;
esac

repo_root=$(git rev-parse --show-toplevel)
remote_ref="refs/remotes/origin/$PAGES_BRANCH"
orphan_branch=""

# ブランチが無いときに作った一時ブランチは、呼び出し側のリポジトリに残さない。
cleanup() {
  git -C "$repo_root" worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
  if [ -n "$orphan_branch" ]; then
    git -C "$repo_root" branch -D "$orphan_branch" > /dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# 他のワークフロー(Storybook 本体のデプロイ・別 PR のレポート)と同じブランチへ
# push するので、競合したら fetch からやり直す。
for attempt in 1 2 3 4 5; do
  cleanup
  orphan_branch=""
  rm -rf "$WORKTREE_DIR"

  if git -C "$repo_root" fetch --no-tags origin "+refs/heads/$PAGES_BRANCH:$remote_ref" 2>/dev/null; then
    git -C "$repo_root" worktree add --detach "$WORKTREE_DIR" "$remote_ref"
  else
    git -C "$repo_root" worktree add --detach "$WORKTREE_DIR"
    orphan_branch="storybook-vrt-$PAGES_BRANCH-$$-$attempt"
    git -C "$WORKTREE_DIR" checkout --quiet --orphan "$orphan_branch"
    git -C "$WORKTREE_DIR" rm -rf --quiet --ignore-unmatch .
  fi

  rm -rf "${WORKTREE_DIR:?}/$TARGET_PATH"
  if [ -n "$SOURCE_DIR" ]; then
    mkdir -p "$WORKTREE_DIR/$TARGET_PATH"
    cp -r "$SOURCE_DIR/." "$WORKTREE_DIR/$TARGET_PATH/"
    if [ -n "$REPORT_VERSION" ]; then
      SUMMARY="$WORKTREE_DIR/$TARGET_PATH/summary.json" node -e 'const summary = require(process.env.SUMMARY); if (summary.reportVersion !== process.env.REPORT_VERSION) process.exit(1)'
    fi
  fi
  touch "$WORKTREE_DIR/.nojekyll"

  git -C "$WORKTREE_DIR" add -A
  if git -C "$WORKTREE_DIR" diff --cached --quiet; then
    echo "no changes to publish"
    exit 0
  fi
  git -C "$WORKTREE_DIR" \
    -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit --quiet -m "$COMMIT_MESSAGE"

  if git -C "$WORKTREE_DIR" push origin "HEAD:refs/heads/$PAGES_BRANCH"; then
    exit 0
  fi
  echo "push failed (attempt $attempt), retrying..."
  sleep $((attempt * 2))
done

echo "::error::failed to push to $PAGES_BRANCH after 5 attempts"
exit 1
