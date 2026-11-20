# tally

Count lines, words and bytes of files and directories, with totals per file type. One static executable, no runtime to install.

```sh
nabi install tally
tally src/ README.md
```

```
src/main.nabi    412 lines   1,804 words   13,920 bytes
README.md         38 lines     240 words    1,532 bytes
.nabi            412 lines   1,804 words   13,920 bytes
total            450 lines   2,044 words   15,452 bytes
```

## Options

- `--by ext`: totals per extension (the default) or `--by dir`.
- `--json`: one JSON object per file, for scripts.
- `--exclude <glob>`: skip matching paths; `.gitignore` is honoured.
