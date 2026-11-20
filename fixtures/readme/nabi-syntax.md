# nabi-syntax

Syntax highlighting for Nabi and NABION, in one place:

| Path | What |
|------|------|
| `grammars/nabi.tmLanguage.json`, `grammars/nabion.tmLanguage.json` | TextMate grammars (`source.nabi`, `source.nabion`) |
| `tree-sitter/nabi/`, `tree-sitter/nabion/` | tree-sitter grammars and queries |
| `src/` | the Nabi library: a tokenizer and HTML highlighter |
| `corpus/` | small `.nabi` / `.nabion` files with the scopes every highlighter must give |
| `grammars/classes.nabion`, [`docs/token-classes.md`](docs/token-classes.md) | the token classes: TextMate scope, tree-sitter capture, LSP type, library `Kind` |
| `grammars/keywords.nabion` | the keywords of each class |

All three implementations are tested against the same corpus and keep
the same keyword rules ([docs/token-classes.md](docs/token-classes.md));
[`grammars/keywords.nabion`](grammars/keywords.nabion) lists the keywords.

## Editors

- VS Code: [nabi.vscode](https://github.com/nabi-lang/nabi.vscode) ships
  the TextMate grammars.
- Vim and Neovim: [nabi.vim](https://github.com/nabi-lang/nabi.vim) ships
  the queries for Neovim and Vim syntax files made from the keyword
  lists.
- Zed: [nabi.zed](https://github.com/nabi-lang/nabi.zed) pins the
  tree-sitter grammars and ships the queries with Zed's capture names.
- Semantic tokens from `nabils` cover only what no static grammar can
  know (macros, user-defined suffixes, keywords and operators); map them
  with the LSP column of the table.

### TextMate

`grammars/nabi.tmLanguage.json` (`source.nabi`, for `.nabi`) and
`grammars/nabion.tmLanguage.json` (`source.nabion`, for `.nabion`) work in
any TextMate host: VS Code, Shiki, GitHub Linguist, Sublime Text, bat.
Scopes follow the TextMate naming conventions, so stock themes color
them. With Shiki:

```js
import nabi from "./nabi.tmLanguage.json" with { type: "json" };
const html = await codeToHtml(src, { lang: "nabi", langs: [{ ...nabi, name: "nabi" }], theme: "github-dark" });
```

### tree-sitter

The grammars are `tree-sitter/nabi` and `tree-sitter/nabion`; the parsers
in `src/` are generated and checked in, so an editor needs only a C
compiler. Each has `queries/highlights.scm`, `locals.scm`,
`injections.scm`, `folds.scm` and `indents.scm`. Capture names follow
nvim-treesitter (`@keyword.conditional`, `@function.call`,
`@string.escape`).

Neovim, with nvim-treesitter's `master` branch (nabi.vim does this for
you and ships the queries):

```lua
local parsers = require("nvim-treesitter.parsers").get_parser_configs()
parsers.nabi = {
  install_info = {
    url = "https://github.com/nabi-lang/nabi-syntax",
    location = "tree-sitter/nabi",
    files = { "src/parser.c", "src/scanner.c" },
    branch = "main",
  },
  filetype = "nabi",
}
parsers.nabion = {
  install_info = {
    url = "https://github.com/nabi-lang/nabi-syntax",
    location = "tree-sitter/nabion",
    files = { "src/parser.c", "src/scanner.c" },
    branch = "main",
  },
  filetype = "nabion",
}
```

Then `:TSInstall nabi nabion`. Without nabi.vim, copy
`tree-sitter/nabi/queries/*.scm` to `queries/nabi/` and
`tree-sitter/nabion/queries/*.scm` to `queries/nabion/` on your
`runtimepath`, and start highlighting with `vim.treesitter.start()` in
a `FileType nabi,nabion` autocommand.

Helix, in `languages.toml`:

```toml
[[language]]
name = "nabi"
scope = "source.nabi"
file-types = ["nabi"]
roots = ["nabi.nabion"]
comment-token = "//"
block-comment-tokens = { start = "/*", end = "*/" }
indent = { tab-width = 4, unit = "    " }
language-servers = ["nabils"]

[[grammar]]
name = "nabi"
source = { git = "https://github.com/nabi-lang/nabi-syntax", rev = "COMMIT", subpath = "tree-sitter/nabi" }

[language-server.nabils]
command = "nabils"
```

Add the same `[[language]]` and `[[grammar]]` for `nabion` (file type
`nabion`, subpath `tree-sitter/nabion`, no language server), run
`hx --grammar fetch && hx --grammar build`, and copy the queries to
`~/.config/helix/runtime/queries/nabi/` and `.../queries/nabion/`. Helix
themes color most captures by prefix (`keyword.*`, `type.*`,
`string.*`, `function.*`); a few nvim-treesitter names (`@boolean`,
`@number`, `@character`, `@module`, `@property`) need theme entries.

Zed ([nabi.zed](https://github.com/nabi-lang/nabi.zed) does this): a Zed
extension names the grammar in its `extension.toml` and carries the
queries in `languages/nabi/` with a `config.toml` (`name = "Nabi"`,
`grammar = "nabi"`, `path_suffixes = ["nabi"]`):

```toml
[grammars.nabi]
repository = "https://github.com/nabi-lang/nabi-syntax"
rev = "COMMIT"
path = "tree-sitter/nabi"
```

## The Nabi library

[docs.nabi-lang.org](https://docs.nabi-lang.org) and
[packages.nabi-lang.org](https://packages.nabi-lang.org) use it for code blocks.

```nabion
Package {
    deps: { "nabi-syntax": "0.1" },
}
```

Needs Nabi 0.1 or later.

```nabi
let html = nabi_syntax::highlight_nabi("let x: i32 = f\"{y:>8}\";");
println(f"<pre><code>{html}</code></pre>");

for t in nabi_syntax::tokens("fn main() {}") {
    println(f"{t.kind:?} {t.text:?}");
}
```

| Item | Description |
|------|-------------|
| `highlight_nabi(src: str) -> str`    | Nabi source to HTML. Tokens become `<span class="...">`; `&` `<` `>` are escaped. Put the result inside `<pre><code>` |
| `highlight_nabion(src: str) -> str`  | NABION source to HTML. The only keywords are `true` / `false` / `none`; a name before `:` is a field |
| `tokens(src: str) -> List<Token>`   | Tokens of Nabi source. Concatenating every token's `text` gives back the source |
| `tokens_nabion(src: str) -> List<Token>` | Tokens of NABION source |
| `to_html(toks: List<Token>) -> str` | Tokens to the same HTML as `highlight_*` |
| `Token { kind: Kind, text: str }`   | A piece of the source |
| `Kind`                              | `Keyword` `Type` `Str` `Number` `Comment` `Attribute` `Text` `Macro` |
| `Kind::class(self) -> str`          | The token's CSS class: `k` `t` `s` `n` `c` `a` `m`; `""` for `Text` (no span) |

`Macro` (`m`) marks macro calls (`log!`) and meta template tokens
(`@macro`, `@Self`); a stylesheet without an `m` rule shows them as
plain text.

## Development

```bash
npm ci && npm test   # TextMate and tree-sitter grammars against corpus/
nabi test             # the library, against the same corpus
nabi bench            # benchmarks
nabi fmt --check
nabi doc              # API docs in target/doc/
```

`npm run test:textmate` and `npm run test:tree-sitter` run one runner;
`--dump FILE` on either script prints the scopes or captures of each
line, which helps when writing corpus assertions.

The tree-sitter grammars (tree-sitter CLI 0.27, from `npm ci`):

```bash
cd tree-sitter/nabi
../../node_modules/.bin/tree-sitter generate      # after editing grammar.js
../../node_modules/.bin/tree-sitter test --config-path test/config.json
node ../scripts/smoke.ts --grammar nabi --docs ../../../docs/learn \
    --cases ../../../nabi/tests/cases
```

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
