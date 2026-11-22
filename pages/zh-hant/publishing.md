## 套件登錄庫

**packages.nabi-lang.org** 是 Nabi 的套件登錄庫。這裡的一個套件就是一個 git 儲存庫，根目錄有 `nabi.nabion`，原始碼放在 `src/`。登錄庫的資料只有一個 git 儲存庫，也就是[索引](https://github.com/nabi-lang/packages-index)。每個版本指向套件自己儲存庫中的一個提交，登錄庫保存該提交的壓縮檔，`nabi` 會下載它並與索引比對。每一行的格式請見[索引 README](https://github.com/nabi-lang/packages-index#readme)。

使用與發布套件的指南在 Nabi 文件中。本頁是其精簡版。

## 使用套件

```sh
nabi add json            # 與最新版本相容的範圍（^0.1.0）
nabi add http@^0.1       # 明確指定範圍
```

`nabi add` 會在 `nabi.nabion` 的 `deps` 寫入一行；下一次 `nabi build` 會在範圍內選出最高的版本（略過已撤回的版本），並固定在 `nabi.lock` 中。標示為**官方**的套件由 nabi-lang 組織發布，隨工具鏈一起提供：使用它的程式在第一次執行時就會加入它。標示為 **bin** 的套件附有執行檔，用 `nabi install <name>` 安裝。

延伸閱讀：指南第 11 章的[套件登錄庫](https://docs.nabi-lang.org/latest/zh-hant/learn/11-modules-packages#套件登錄庫)。

## 發布套件

```sh
nabi login                # 在帳戶頁面建立的權杖
nabi publish --dry-run    # 只印出索引項目，不會傳送任何東西
nabi publish
nabi yank <name>@0.3.1    # 新的相依解析會略過它，現有的鎖定檔照常運作
```

誤發布的版本在發布後 72 小時內、且沒有其他套件相依於它時可以刪除：在[帳戶頁面](/zh-hant/me#versions)刪除，或使用 `DELETE /api/v1/packages/<name>/<version>`（請見 [API 參考](/zh-hant/api#刪除版本)）。它的版本號不會再被使用。超過這段時間後，請將它撤回。

目前還不是每個人都能發布：權杖與受信任的發布者暫時只供登錄庫的維護者使用。權杖在[帳戶頁面](/zh-hant/me)建立，套件的擁有者也在那裡邀請其他擁有者、新增受信任的發布者。名稱先到先得，但須遵守[使用政策](/zh-hant/policy)。

更多內容請見指南的[功能特性與發布](https://docs.nabi-lang.org/latest/zh-hant/learn/18-features-and-publishing)：

- 套件需要什麼，`nabi login`、`nabi publish`，名稱與擁有者，登錄庫產生的 API 文件，`nabi yank`
- 受信任發布（trusted publishing）：不儲存權杖，從 GitHub Actions 發布，以及可直接複製的工作流程
- 維持 API 穩定：`#[deprecated]`、`#[non_exhaustive]` 與 `#[sealed]`

## 登錄庫 API

套件資訊、README、原始碼壓縮檔與文件對所有人開放，可從任何來源以 NABION 或 JSON 讀取：請見 [API 參考](/zh-hant/api)。每個套件也有一個顯示最新版本的徽章，可放進 README，位址是 `/packages/<name>/badge.svg`。
