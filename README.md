# storybook-vrt-action

Storybook のビジュアルリグレッションテスト(VRT)を GitHub Actions だけで回す composite action です。
外部サービスは使わず、ベースラインとレポートはリポジトリの GitHub Pages 用ブランチ(既定 `gh-pages`)に置きます。

- main に入った Storybook を撮影して **ベースライン** として保存する
- PR の Storybook を撮影してベースラインと比較し、**レポート** を Pages へ公開して PR にコメントする
- 差分があればチェックを赤にする。意図した変更なら PR に **`visual-approved` ラベル** を付けると通る

比較には [odiff](https://github.com/dmtrKovalenko/odiff) を使い、撮影はランナーにある Chrome を DevTools Protocol で直接動かします(Playwright などは不要)。

## しくみ

```
main へ push ── build ── capture ──▶ gh-pages:/visual-baseline/
                                                │
PR ─────────── build ── capture ── compare ◀────┘
                                      │
                                      ├─▶ gh-pages:/visual-regression/pr-<番号>/  (レポート)
                                      ├─▶ PR へのコメント(Changed / New / Deleted / Passed)
                                      └─▶ チェックの成否(承認ラベルがあれば差分があっても通す)
PR を閉じる ───────────────────────────▶ gh-pages:/visual-regression/pr-<番号>/ を削除
```

レポートは reg-viz と同じ 4 分類(Changed / New / Deleted / Passed)で、各ストーリーを Diff / Slide / 2up / Blend / Toggle の 5 つのモードで見比べられます。

- **Changed** だけが失敗に数えられます。New(ベースラインに無い)と Deleted(今回無い)は退行ではないので落としません
- 画素の違いが `max-diff-ratio`(既定 0.2%)以下なら Passed になります
- 撮影は描画が落ち着く(同じフレームが 2 回続く)まで待ってから行います
- ストーリーが撮影範囲(既定 1280x720)からはみ出していると、はみ出た部分は比較されないので **撮影を失敗させます**。ストーリーに大きさの決まった器(decorator)を与えてください
- ランナーに CJK フォントが無いと日本語が豆腐(□)のまま「差分なし」でベースラインに焼き付くため、既定で `fonts-noto-cjk` を入れ、豆腐になる環境なら撮影前に落とします

## 準備

1. リポジトリの **Settings → Pages** で、Source を「Deploy from a branch」・ブランチを `gh-pages`(ルート)にする
   - `gh-pages` ブランチが無ければ、初回の実行で空の orphan ブランチとして作られます
2. ワークフローに次の権限を与える

| 権限 | 用途 |
|---|---|
| `contents: write` | `gh-pages` への push |
| `pull-requests: write` / `issues: write` | PR へのコメント・承認ラベルの作成と参照 |
| `pages: write` | 配信が取り残されたときに Pages のビルドを 1 回だけ要求する(無くても動くが、そのときは待つだけになる) |

## 使い方

### main: ベースラインを撮る

```yaml
# .github/workflows/visual-baseline.yml
name: Visual baseline

on:
  push:
    branches: [main]

permissions:
  contents: write

concurrency:
  group: visual-baseline
  cancel-in-progress: true

jobs:
  baseline:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
      - uses: pnpm/action-setup@v5
      - uses: actions/setup-node@v6
        with:
          node-version: 24
          cache: pnpm
      - run: pnpm install --frozen-lockfile

      - uses: DIO0550/storybook-vrt-action@v1
        with:
          mode: baseline
          build-command: pnpm build-storybook
```

### PR: 比較してレポートを出す

```yaml
# .github/workflows/visual-regression.yml
name: Storybook Visual Regression

on:
  pull_request:
    # labeled / unlabeled は承認ラベルの付け外しでチェックを切り替えるため
    types: [opened, reopened, synchronize, closed, labeled, unlabeled]

permissions:
  contents: write
  pull-requests: write
  issues: write
  pages: write

concurrency:
  group: visual-regression-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  visual-regression:
    # 無関係なラベルの付け外しでは走らせない(job の if は env を読めないので綴りを直接書く)。
    # フォークの PR では GITHUB_TOKEN が read-only になり gh-pages へ push できないので外す。
    if: >-
      github.event.pull_request.head.repo.full_name == github.repository
      && ((github.event.action != 'labeled' && github.event.action != 'unlabeled')
          || github.event.label.name == 'visual-approved')
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
      - uses: pnpm/action-setup@v5
        if: github.event.action != 'closed'
      - uses: actions/setup-node@v6
        if: github.event.action != 'closed'
        with:
          node-version: 24
          cache: pnpm
      - run: pnpm install --frozen-lockfile
        if: github.event.action != 'closed'

      - uses: DIO0550/storybook-vrt-action@v1
        with:
          build-command: pnpm build-storybook
          # 任意。PR プレビューを別に配信しているならコメントにリンクを載せる
          storybook-url: https://${{ github.repository_owner }}.github.io/${{ github.event.repository.name }}/pr-preview/pr-${{ github.event.pull_request.number }}/
```

PR が閉じられたとき(`closed`)は撮影せず、その PR のレポートを `gh-pages` から消すだけです。

### Storybook 本体と一緒にデプロイしている場合

main のデプロイで `gh-pages` のルートを丸ごと置き換えていると、`mode: baseline` が置いた `visual-baseline/` も消えてしまいます。
その場合は `mode: capture` で撮影だけを行い、自前のデプロイにベースラインを同梱してください(`visual-regression/` もデプロイで消さないようにします)。

```yaml
      - uses: DIO0550/storybook-vrt-action@v1
        with:
          mode: capture
          storybook-dir: storybook-static
          output-dir: visual-baseline   # この中身を gh-pages:/visual-baseline/ に置く
```

## 差分が出たら

1. PR のコメントにある **VRT report** を開いて差分を確認する
2. **意図した変更** なら PR に `visual-approved` ラベルを付ける。チェックが再実行され、差分があっても通る
3. **意図しない変更** ならコードを直す(ラベルで通さない)

- ラベルはリポジトリに無ければ、差分が出たときに自動で作られます
- ラベルを外すと再びチェックが走り、差分が残っていれば赤に戻ります
- ベースラインは main へマージされた時点で撮り直されます

## 入力

| 名前 | 既定値 | 説明 |
|---|---|---|
| `mode` | `compare` | `compare`(PR で比較)/ `baseline`(撮影してベースラインとして公開)/ `capture`(撮影だけ) |
| `github-token` | `${{ github.token }}` | コメント・ラベル操作・Pages のビルド要求に使うトークン |
| `working-directory` | `.` | `build-command` を実行し、`storybook-dir` を解決する基準 |
| `build-command` | | 撮影前に実行する Storybook のビルドコマンド。空ならビルド済みの `storybook-dir` を使う |
| `storybook-dir` | `storybook-static` | ビルド済み Storybook(`index.json` と `iframe.html` があること) |
| `output-dir` | `visual-baseline` | `mode: capture` の書き出し先(`working-directory` からの相対) |
| `pages-branch` | `gh-pages` | ベースラインとレポートを置くブランチ |
| `baseline-path` | `visual-baseline` | `pages-branch` 内のベースラインのパス |
| `report-path` | `visual-regression` | `pages-branch` 内のレポートのパス(`<report-path>/pr-<番号>/`) |
| `pages-url` | `https://<owner>.github.io/<repo>` | `pages-branch` の配信 URL(独自ドメインなら指定する) |
| `wait-for-pages` | `true` | レポートが実際に配信されるまで待つか |
| `pages-timeout-seconds` | `600` | 配信を待つ上限。出なければビルドを 1 回要求してもう一度待つ |
| `approval-label` | `visual-approved` | このラベルがあれば差分があっても通す |
| `fail-on-diff` | `true` | 承認されていない差分があるとき失敗させるか |
| `comment` | `true` | PR にコメントするか |
| `comment-title` | `Storybook visual regression` | コメントの見出し(変えると別のコメントになる) |
| `storybook-url` | | コメントに載せる Storybook の URL |
| `max-diff-ratio` | `0.002` | この割合を超えて画素が違うと Changed |
| `threshold` | `0.1` | 1 画素を違うとみなす色差(odiff の `threshold`) |
| `viewport-width` / `viewport-height` | `1280` / `720` | 撮影サイズ |
| `settle-ms` | `750` | ストーリーを開いてから最初に撮るまでの待ち |
| `stable-poll-ms` / `stable-timeout-ms` | `250` / `8000` | 描画が落ち着いたかを確かめる間隔と上限 |
| `allow-overflow` | `false` | 撮影範囲からはみ出すストーリーがあっても失敗させない |
| `font-packages` | `fonts-noto-cjk` | 撮影前に apt で入れるフォント(空なら入れない) |
| `require-japanese-font` | `true` | 日本語が豆腐になる環境なら撮影前に失敗させる |
| `node-version` | `24` | `actions/setup-node` で用意する Node.js(22 以上)。空なら PATH の node を使う |
| `artifact-name` | `storybook-visual-report` | レポートを上げる artifact の名前(空なら上げない) |

## 出力

| 名前 | 説明 |
|---|---|
| `result` | `passed` / `approved` / `changed` / `error` / `skipped`(`compare` 以外、または撮影しなかったとき) |
| `changed` / `new` / `deleted` / `passed` | 各分類の件数 |
| `report-url` | 公開したレポートの URL |
| `report-dir` | ランナー上のレポートのディレクトリ |
| `screenshots-dir` | ランナー上の撮影結果のディレクトリ |

## 手元で動かす

```bash
npm ci
npx storybook build                     # 撮りたいリポジトリで
node scripts/storybook-visual-regression.mjs capture --storybook-dir path/to/storybook-static --out visual-actual
node scripts/storybook-visual-regression.mjs compare --expected visual-baseline --actual visual-actual --out visual-report
open visual-report/index.html
```

Chrome は `google-chrome` / `chromium` を PATH から探します。別の場所にあるなら `CHROME_BIN` で指定してください。

## 開発

```bash
npm ci
bash test/vrt.test.sh            # 撮影 → 比較 → 検証(フィクスチャの Storybook を使う)
bash test/publish-pages.test.sh  # gh-pages への公開(ローカルの bare リポジトリを使う)
```

## License

MIT
