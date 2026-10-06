# dopagaki

Claude Code の画面を虹色にする Mod です。テーマは「見ているだけで脳汁が出る、でも普通に使える」。

本体のファイルは書き換えません。描画を差し替えるのは Claude Code の Mod(plugin の function hooks)の仕組みです。そのため、バックアップを取る必要も、アップデートのたびに当て直す必要もありません。

## 一発インストール(Mod + 虹色ステータスライン)

ターミナルで次の 1 行を実行します。

```sh
curl -fsSL https://raw.githubusercontent.com/000ts/dopagaki-claude-code/main/install.sh | bash
```

dopagaki Mod と、虹色のステータスライン([claude-code-dopagaki-line](https://github.com/000ts/claude-code-dopagaki-line))をまとめて入れます。`~/.claude/settings.json` の `statusLine` を書き換えます。書き換え前のファイルは `settings.json.<日時>.bak` として残ります。新しく開いたセッションから有効になります。

## Mod だけを入れる

Claude Code のプロンプトで次を実行します。

```
/plugin install dopagaki --marketplace 000ts/dopagaki-claude-code
```

`Add marketplace?` には `y`、スコープは user のまま Enter。以後のすべてのセッションで有効になります。

## 何が変わるか

| 箇所 | 演出 |
|---|---|
| スピナーの記号 | 円弧 `◜ ◠ ◝ ◞ ◡ ◟` が時計回りに回り続ける(6 フレームをループ、1 フレーム 100ms)。色相は 1 フレームに 6° ずつ回る。明滅はしない |
| スピナーの文言 | 虹色で流れる。文言そのものは本体のまま |
| スピナーの括弧内 | 経過時間・トークン数・思考状態を出す。トークン数は太字の虹色で流れながら、0.5 秒ごとに左右へゆっくり揺れ、思考状態はゆらゆら揺れる |
| `✻ Baked for 3s` 行 | 先頭の記号を虹色の `✔` にする。文言と色は元のまま(薄い灰色)。ただし元の行に付く `· done 時刻`、バックグラウンド処理待ち、`still running` などの付加情報は出なくなる |
| 自分のプロンプト行 | 先頭の `>` だけ虹色。本文は通常色 |
| 入力欄の下のモード表示 | 虹色 |
| 入力欄の上 | 作業中だけ、虹色のバーが流れる |

アニメーションが動くのはターンの実行中だけです。待機中は描き直しません。

アシスタントの返答、ツール実行、エラー表示、ダイアログには手を入れていません。

## オン・オフ

```
/dopagaki off   # 全部を本体の表示に戻す
/dopagaki on
/dopagaki       # 切り替え
```

選んだ状態は保存され、次のセッションでも引き継がれます。

環境変数 `NO_COLOR` が設定されていると、色は付けません(円弧のアニメーションはそのまま)。

## 手元のフォルダから読み込む(開発用)

置き場所は `~/claude-mods/dopagaki` です。`~/.claude/settings.json` の `env` に次の設定があるので、すべてのセッションで読み込まれます。

```json
{ "env": { "CLAUDE_CODE_PLUGIN_DIRS": "~/claude-mods/dopagaki" } }
```

1 回だけ別の場所の版を試すときは `claude --plugin-dir <フォルダ>` を使います。

## 元に戻す

- 一時的に戻す:`/dopagaki off`
- 完全に外す:`CLAUDE_CODE_PLUGIN_DIRS` から外す(または `--plugin-dir` を付けずに起動する)。そのうえでフォルダを削除する

本体には何も書き込んでいないので、これで元どおりになります。

## Claude Code をアップデートしたあと

再適用の作業はありません。ただし Mod の API は早期アクセス段階で、変わることがあります。アップデート後に表示がおかしくなったら、次を実行してください。

```sh
claude plugin validate ~/claude-mods/dopagaki   # エンジンが受け付けない書き方がないか
claude plugin test ~/claude-mods/dopagaki       # 振る舞いのテスト
```

Mod が描画に失敗した箇所は、エンジンが自動で本体の表示に戻します。表示が壊れたまま使えなくなることはありません。

## 開発

- 本体:`hooks/register.tsx`
- テスト:`hooks/register.test.tsx`
- 記号のフレーム間隔:`ARC_MS`。記号は 1×1 の `Raster` で、`$.ui.blit` で差し替える。blit は 1 秒 120 回まで受け付け、表示は 60 回前後なので、16ms 程度まで縮められる
- 記号の色相の進み:`ARC_HUE_STEP`
- 文言の虹色とそのほかの演出の間隔:`FRAME_MS`。`ui.render` の再描画は 1 秒 10 回が上限なので、100ms より短くしても速くならない
