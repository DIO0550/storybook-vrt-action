#!/usr/bin/env node
// 自己テスト用に、`storybook build` の出力と同じ形(index.json + iframe.html)の最小 Storybook を作る。
//
// usage: node test/make-fixture.mjs <base|changed|added|overflow> <out-dir>
//   base     ... 3 ストーリー
//   changed  ... base のボタンの色だけを変えたもの(Changed が 1 件になる)
//   added    ... base に 1 ストーリー足したもの(New が 1 件になり、チェックは落ちない)
//   overflow ... 撮影範囲(既定 1280x720)より高いストーリーを含むもの(撮影が落ちる)
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [variant, out] = process.argv.slice(2);
const variants = ["base", "changed", "added", "overflow"];
if (!variants.includes(variant) || !out) {
  console.error(`usage: make-fixture.mjs <${variants.join("|")}> <out-dir>`);
  process.exit(2);
}

const story = (id, title, name, html) => ({ id, title, name, html });
const buttonColor = variant === "changed" ? "#e8384f" : "#1f8ceb";
const stories = [
  story("example-button--primary", "Example/Button", "Primary", `<button style="background:${buttonColor};color:#fff;border:0;border-radius:6px;padding:12px 24px;font:16px sans-serif">Button</button>`),
  story("example-text--japanese", "Example/Text", "Japanese", `<p style="font:24px sans-serif">日本語のテキスト</p>`),
  story("example-card--default", "Example/Card", "Default", `<div style="width:320px;height:180px;border:1px solid #ccc;border-radius:8px;box-shadow:0 2px 8px #0002"></div>`),
];
if (variant === "added") {
  stories.push(story("example-badge--default", "Example/Badge", "Default", `<span style="background:#2b3a3c;color:#fff;padding:4px 10px;border-radius:999px;font:14px sans-serif">Badge</span>`));
}
if (variant === "overflow") {
  stories.push(story("example-list--tall", "Example/List", "Tall", `<div style="height:2000px;background:linear-gradient(#fff,#ddd)"></div>`));
}

const entries = Object.fromEntries(stories.map(({ id, title, name }) => [id, { type: "story", id, title, name, importPath: "./fixture.stories.js" }]));
const bodies = Object.fromEntries(stories.map(({ id, html }) => [id, html]));
const iframe = `<!doctype html>
<html><head><meta charset="utf-8"><style>body{margin:0;padding:16px;background:#fff}</style></head>
<body><div id="root"></div>
<script>
  const bodies = ${JSON.stringify(bodies).replaceAll("<", "\\u003c")};
  const id = new URLSearchParams(location.search).get("id");
  document.getElementById("root").innerHTML = bodies[id] ?? "unknown story";
</script></body></html>
`;

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
writeFileSync(join(out, "index.json"), JSON.stringify({ v: 5, entries }, null, 2));
writeFileSync(join(out, "iframe.html"), iframe);
writeFileSync(join(out, "index.html"), "<!doctype html><title>fixture</title>");
console.log(`wrote ${variant} fixture with ${stories.length} stories to ${out}`);
