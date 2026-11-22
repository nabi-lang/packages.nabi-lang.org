## 包注册表

**packages.nabi-lang.org** 是 Nabi 的包注册表。其中的一个包就是一个 git 仓库，根目录下有 `nabi.nabion`，源代码在 `src/` 中。注册表的数据只有一个 git 仓库，即[索引](https://github.com/nabi-lang/packages-index)。每个版本指向包自身仓库中的一个提交，注册表保存该提交的压缩包，`nabi` 下载它并与索引核对。每行的格式见[索引 README](https://github.com/nabi-lang/packages-index#readme)。

使用和发布包的指南在 Nabi 文档中。本页是它的简要版本。

## 使用包

```sh
nabi add json            # 与最新版本兼容的范围（^0.1.0）
nabi add http@^0.1       # 显式指定范围
```

`nabi add` 在 `nabi.nabion` 的 `deps` 中写入一行；下一次 `nabi build` 在范围内选出最高的版本（跳过已撤回的版本），并固定在 `nabi.lock` 中。标有**官方**的包由 nabi-lang 组织发布，随工具链一起提供：使用它的程序在首次运行时会自动添加它。标有 **bin** 的包带有可执行文件，用 `nabi install <name>` 安装。

更多内容：指南第 11 章的[包注册表](https://docs.nabi-lang.org/latest/zh-hans/learn/11-modules-packages#包注册表)。

## 发布包

```sh
nabi login                # 账户页面上创建的令牌
nabi publish --dry-run    # 只打印索引条目，不向外发送任何内容
nabi publish
nabi yank <name>@0.3.1    # 新的依赖解析会跳过它，已有的锁文件照常工作
```

误发布的版本在发布后 72 小时内、且没有其他包依赖它时可以删除：在[账户页面](/zh-hans/me#versions)上删除，或使用 `DELETE /api/v1/packages/<name>/<version>`（见 [API 参考](/zh-hans/api#删除版本)）。它的版本号不会再次使用。超过这段时间后，请撤回它。

发布尚未向所有人开放：令牌和可信发布者目前只供注册表的维护者使用。令牌在[账户页面](/zh-hans/me)上创建，包的所有者也在那里邀请其他所有者、添加可信发布者。名称先到先得，但须遵守[使用政策](/zh-hans/policy)。

更多内容见指南的[特性与发布](https://docs.nabi-lang.org/latest/zh-hans/learn/18-features-and-publishing)：

- 包需要什么，`nabi login`、`nabi publish`，名称与所有者，注册表生成的 API 文档，`nabi yank`
- 可信发布（trusted publishing）：不保存令牌，从 GitHub Actions 发布，以及可直接复制的工作流
- 保持 API 稳定：`#[deprecated]`、`#[non_exhaustive]` 和 `#[sealed]`

## 注册表 API

包信息、README、源代码压缩包和文档对所有人开放，可从任何来源以 NABION 或 JSON 读取：见 [API 参考](/zh-hans/api)。每个包还有一个显示最新版本的徽章，可放进 README，地址为 `/packages/<name>/badge.svg`。
