#!/usr/bin/env bash
# scripts/publish-pages.sh を、ローカルの bare リポジトリを origin にして確かめる。
#
# usage: bash test/publish-pages.test.sh [work-dir]
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work="${1:-$(mktemp -d)}"
fail() { echo "FAIL: $*" >&2; exit 1; }
# origin の gh-pages にあるファイルの一覧
tree_of() { git -C "$work/origin.git" ls-tree -r --name-only gh-pages | sort | tr '\n' ' '; }

rm -rf "$work"
mkdir -p "$work"
git init --quiet --bare "$work/origin.git"
git init --quiet "$work/clone"
git -C "$work/clone" -c user.name=t -c user.email=t@example.com commit --quiet --allow-empty -m init
git -C "$work/clone" remote add origin "$work/origin.git"
git -C "$work/clone" push --quiet origin HEAD:refs/heads/main

mkdir -p "$work/report-a" "$work/report-b"
echo '{"reportVersion":"a"}' > "$work/report-a/summary.json"
echo '{"reportVersion":"b"}' > "$work/report-b/summary.json"

publish() {
  (cd "$work/clone" && env PAGES_BRANCH=gh-pages WORKTREE_DIR="$work/wt" COMMIT_MESSAGE=test "$@" bash "$root/scripts/publish-pages.sh")
}

# ブランチが無ければ orphan で作る
publish TARGET_PATH=visual-regression/pr-1 SOURCE_DIR="$work/report-a" REPORT_VERSION=a
[ "$(tree_of)" = ".nojekyll visual-regression/pr-1/summary.json " ] || fail "unexpected tree after first publish: $(tree_of)"
[ "$(git -C "$work/origin.git" rev-list --count gh-pages)" = 1 ] || fail "gh-pages should start as an orphan"
echo "ok: creates the branch as an orphan"

# 別のパスには触れない
publish TARGET_PATH=visual-baseline SOURCE_DIR="$work/report-b"
[ "$(tree_of)" = ".nojekyll visual-baseline/summary.json visual-regression/pr-1/summary.json " ] || fail "other paths were touched: $(tree_of)"
echo "ok: keeps other paths"

# 置き換えると古い中身は残らない
rm "$work/report-b/summary.json"
echo 'x' > "$work/report-b/a.png"
publish TARGET_PATH=visual-baseline SOURCE_DIR="$work/report-b"
[ "$(tree_of)" = ".nojekyll visual-baseline/a.png visual-regression/pr-1/summary.json " ] || fail "stale files remain: $(tree_of)"
echo "ok: replaces the target path"

# 変更が無ければコミットしない
before=$(git -C "$work/origin.git" rev-parse gh-pages)
publish TARGET_PATH=visual-baseline SOURCE_DIR="$work/report-b"
[ "$(git -C "$work/origin.git" rev-parse gh-pages)" = "$before" ] || fail "committed without changes"
echo "ok: no commit without changes"

# SOURCE_DIR が空ならそのパスを消す
publish TARGET_PATH=visual-regression/pr-1 SOURCE_DIR=
[ "$(tree_of)" = ".nojekyll visual-baseline/a.png " ] || fail "path was not removed: $(tree_of)"
echo "ok: removes the target path"

# reportVersion が食い違う中身は公開しない
if publish TARGET_PATH=visual-regression/pr-2 SOURCE_DIR="$work/report-a" REPORT_VERSION=other 2>/dev/null; then
  fail "published a report of another revision"
fi
echo "ok: rejects another revision"

# リポジトリの外を指すパスは受け付けない
if publish TARGET_PATH=../escape SOURCE_DIR="$work/report-a" 2>/dev/null; then
  fail "accepted a target path outside the branch"
fi
echo "ok: rejects paths outside the branch"

# 呼び出し側のチェックアウトを汚さない
[ -z "$(git -C "$work/clone" status --porcelain)" ] || fail "caller checkout is dirty"
[ "$(git -C "$work/clone" branch --list 'storybook-vrt-*')" = "" ] || fail "temporary branches remain"
[ "$(git -C "$work/clone" worktree list | wc -l)" = 1 ] || fail "worktrees remain"
echo "ok: caller checkout is untouched"

echo "all publish-pages tests passed"
