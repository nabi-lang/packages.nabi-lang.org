# markdown

A Nabi library that converts Markdown to HTML. It covers the main parts of
CommonMark plus GitHub extensions (tables, strikethrough, callouts, footnotes,
heading anchors), and renders the pages of docs.nabi-lang.org.

## Add it

```sh
nabi add markdown
```

Needs Nabi 0.1 or later.

## Usage

```nabi
use markdown::render;

let doc = render("# Title\n\nBody *emphasis*\n");
println(doc.html);     // <h1 id="title">...Title</h1> ...
println(doc.title);    // Title
```

Use `render_untrusted` for Markdown of unknown origin, and pass `Options` to map
link destinations or highlight code blocks. There is no highlighter dependency;
pass one through `Options.code` (pairs well with
[nabi-syntax](https://github.com/nabi-lang/nabi-syntax)).

## Docs

https://packages.nabi-lang.org/packages/markdown/latest/docs

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at
your option.
