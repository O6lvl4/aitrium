<h1 align="center">Aitrium</h1>

<p align="center">
  コーディングエージェントが働くための世界。道具はカーネルが強制するサンドボックスの中で動き、<br>
  鍵はその外に置かれる。
</p>

<p align="center">
  <a href="README.md"><img alt="English" src="https://img.shields.io/badge/English-d0d7de?style=flat-square"></a>
  <a href="README.ja.md"><img alt="日本語" src="https://img.shields.io/badge/%E6%97%A5%E6%9C%AC%E8%AA%9E-24292f?style=flat-square"></a>
</p>

---

> 古代ローマの家では、玄関（*porta*）をくぐると、すぐにアトリウムという中庭の広間に出た。
> 客はそこで迎え入れられ、家の仕事も主人の目の届くそこで進んだ。金庫もその広間に置かれていたが、
> 鍵を持つのは主人だった。

aitrium は、コーディングエージェントのためのその広間だ。エージェントは porta を通って入り、
そこで何をしてよいか（書ける場所、読める場所、通信できる宛先）は家の主人が決める。
エージェントは広間で働き、鍵は主人の手元に残る。

**状態：[計画](docs/design.md) のフェーズ 2。** comide が実行するコマンドはすべて porta を
通り、どれにも鍵は入らない。自分でモデルを呼ぶ golemide にも偽の値だけを渡し、porta の
プロキシがモデルの宛先でだけ本物の鍵に差し替える（almide/porta#37）。これは porta の
develop と Almide v0.65.1-rc2 以降（`aitrium --help` を参照）に依っている。`AITRIUM_CREDENTIALS=by-name`
にすると、golemide には鍵そのものを渡す。

```sh
curl -fsSL https://raw.githubusercontent.com/O6lvl4/aitrium/main/install.sh | sh
```

リリースには aitrium が動かすもの一式が入っている。comide、golemide、porta、gramide、hew、
ctxgate を、[dist/PARTS](dist/PARTS) のコミットでまとめてビルドしたもの。
`~/.local/share/aitrium` に展開し、`~/.local/bin/aitrium` からリンクするだけなので、手元の
comide や porta はそのまま残る。対応は Apple silicon の macOS と、x86_64 か aarch64 の
Linux（静的リンクの musl 版なので、Alpine も含めてディストリビューションを選ばない）。鍵は comide と golemide が読む場所（`~/.config/golemide/.env` か環境変数）に置く。

```sh
aitrium                       # comide の会話。道具のコマンドはすべて縛られる
aitrium -p "fix the tests"    # 1 回だけの依頼。comide の引数はそのまま使える
```

aitrium は隣にある comide と porta を使う。クローンから動かすときは、comide（`--runner` の
ある 0.5.0 以降、O6lvl4/comide#2）と porta を `PATH` に置くか、`AITRIUM_COMIDE` /
`AITRIUM_PORTA` で指定する。`AITRIUM_NET=none` でコマンドの通信を閉じる。
残りは `aitrium --help` に書いてある。

| comide が実行するもの | 書ける場所 | 通信 | 鍵 |
|---|---|---|---|
| `read`（hew、git status） | 作業用のディレクトリ | 無し | 無し |
| `shell`（モデルが書いたコマンド） | プロジェクト、作業用のディレクトリ | 開いている（`AITRIUM_NET`） | 無し |
| `solve`（golemide） | プロジェクト、作業用のディレクトリ | 開いている | 偽の値。porta がモデルの宛先でだけ本物に差し替える（`AITRIUM_CREDENTIALS=by-name` なら鍵そのもの） |

どの呼び出しでも、鍵が置かれたファイル（`~/.config/golemide/.env` など）は読めず、
`TMPDIR` は作業用のディレクトリになり、資格情報の置き場は porta の既定の方針で閉じられる。

その結果として守られることは次の 7 つ。リリースごとに [scripts/host-check.sh](scripts/host-check.sh)
で、コンテナを挟まない Ubuntu 22.04 と 24.04（x86_64 と arm64）の上で、偽の鍵を使い、モデルは
呼ばずに確かめている。

1. コマンドはプロジェクトに書ける。
2. コマンドはホームディレクトリに書けない。
3. コマンドは鍵が置かれたファイルを読めない。
4. コマンドの環境変数に鍵はない。
5. golemide（`solve`）が受け取るのは偽の値（`porta-cred-…`）で、鍵ではない。
6. `solve` の中のどの変数にも鍵はない。
7. golemide も鍵が置かれたファイルを読めない。

これは鍵と書き込みについての約束だ。モデルやタスクが鍵を持ち出そうとしたり、外へデータを
送ろうとしたりしたときに aitrium がどこまで止めるかは、まだ測っていない（#2）。

**Claude のログインで使う。** `aitrium --model claude/sonnet`（または `claude`、`claude/opus`）
とすると、comide は Claude Code の `claude -p` で動く。中の golemide はそのログインを使えない。
ログインが入っているキーチェーンを porta が閉じているからだ。そこで aitrium は 127.0.0.1 に
ブリッジ（`bridge/claude_bridge.py`、`python3` が要る）をセッション限りの合言葉つきで立て、
`solve` にはブリッジの URL と合言葉だけを渡す。ブリッジは comide が終わると止まる。

## 何か

aitrium は、既にある 2 つの道具を組み合わせる。どちらも単体の製品のまま残る。

- [comide](https://github.com/O6lvl4/comide)：ターミナルで動くコーディングエージェント。
  コードの変更は [golemide](https://github.com/O6lvl4/golemide) が受け持つ
- [porta](https://github.com/almide/porta)：コマンドをカーネルで縛る。Linux では
  Landlock と seccomp、macOS では Seatbelt

```
┌─ 外側：監督役 ──────────────────────────────────────────────────┐
│  comide の会話のループと画面 · モデルの呼び出し（almai）          │
│  本物の鍵 · 宛先ごとに鍵を付け替えるプロキシ                     │
│  方針 · 監査の記録 · 人への確認                                 │
└──────────────┬─────────────────────────────────────────────────┘
               │ 道具を 1 回呼ぶごとに
┌──────────────▼── 内側：porta で縛る ───────────────────────────┐
│  shell · 編集 · golemide の solve とその検証コマンド             │
│  空の環境変数 · 書けるのはプロジェクトだけ                       │
│  通信は監督役のプロキシ経由のみ · 見えるのは偽の鍵               │
└────────────────────────────────────────────────────────────────┘
```

エージェントを丸ごとサンドボックスに入れると、モデルの API キーも中に渡すことになる。
そうするとモデルが頼んだどのコマンドからも、その鍵が読める。aitrium は線を道具の
呼び出しのところに引く。エージェントの会話のループは鍵と一緒に外に残り、モデルが実行を
頼んだものは 1 回ずつ中で動く。中から見えるのは、鍵の代わりの偽の値だけになる。

## なぜもう 1 つ作るのか

Cloudflare OS、OpenShell、nono も、鍵をエージェントから遠ざける。aitrium の違いは次のとおり。

- **コードがある場所で動く。** ノート PC でも、CI でも、コンテナの中でも、1 本の静的バイナリ
  で動く。常駐プロセスもクラウドのアカウントも要らない。
- **カーネルが強制する。** 縛りは、エージェントが従う気になるかどうかに依らない。
- **拒否は答えになる。** porta が拒否した内容は、それを通すための指定と一緒に、道具の結果
  としてモデルに返る。モデルは別の道を選ぶことも、人に頼むこともできる。
- **両方のコストを測る。** リリースのたびに、同じ実行で、Terminal-Bench 2.0 で解けた課題の
  数と、防いだ攻撃の数を出す。

## ライセンス

MIT または Apache-2.0。どちらかを選んで使える。
