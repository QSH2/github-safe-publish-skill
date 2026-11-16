# 04 · 不暴露 token 地用 GitHub Actions 发 Release

> 问题：SSH 只能推 git 对象，**不能创建 Release 或上传资产**；网页手动发 6 个版本很慢；
> API 需要 token（手动 PAT 有泄露风险，新账号高频调用又容易触发风控）。
>
> 方案：用 SSH 推一个**临时分支**，里面放「资产 + 发版说明 + 一个工作流」；由 GitHub 自己的
> `GITHUB_TOKEN`（`github-actions[bot]`）在 CI 里执行 `gh release create/upload`；完成后删除临时分支。
> 全程不使用用户密码/长期 token。

---

## 1. 前置条件

- 仓库已存在，目标 tag 已存在（`git ls-remote --tags` 确认）；
- 本地已有每个版本的资产目录：`<work>/release-assets/<tag>/...`（exe/zip/SHA256SUMS 等）；
- 本地已有每个版本的发布说明：`<work>/release-notes/<tag>.md`。

目录示例：

```text
release-assets/
  v1.0.0/  app.exe  src.zip  SHA256SUMS-v1.0.0.txt
  v1.1.0/  ...
release-notes/
  v1.0.0.md
  v1.1.0.md
.github/workflows/create-releases.yml
```

---

## 2. 分支准备（关键：`git add -f`）

**先检查 `.gitignore` 是否吞掉资产**——`*.exe`、`*.zip`、`bin/`、`dist/` 是常见规则：

```powershell
Get-Content .gitignore
& $git check-ignore -v release-assets/v1.0.0/app.exe   # 有输出 = 被忽略
```

若被忽略，必须强制 add，否则 Release 里只有校验和文件：

```powershell
& $git switch -c ci/release-assets main
& $git add -f release-assets
& $git add release-notes .github/workflows/create-releases.yml
& $git -c user.name="<name>" -c user.email="<noreply>" commit -m "ci: temporary release assets"
& $git push origin ci/release-assets
```

> 提交信息**不要带 `[skip ci]`**，否则这次 push 不会触发工作流（本案例踩过：调试提交带
> `[skip ci]`，等了半天没有 run）。

---

## 3. 工作流：幂等创建/更新 Release

把下面模板写到 `.github/workflows/create-releases.yml`（实际生成可用
[`scripts/make-release-workflow.ps1`](../scripts/make-release-workflow.ps1)）：

```yaml
name: create-releases
on:
  push:
    branches: [ ci/release-assets ]

permissions:
  contents: write

jobs:
  create:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Create or update releases
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -e
          gh --version
          if gh release view "v1.0.0" >/dev/null 2>&1; then
            gh release upload "v1.0.0" release-assets/v1.0.0/* --clobber
          else
            gh release create "v1.0.0" --verify-tag \
              --title "v1.0.0 — 首个版本" \
              --notes-file "release-notes/v1.0.0.md" \
              --latest=false release-assets/v1.0.0/*
          fi
          sleep 20
          # ……其余版本重复；最后一个版本不要 --latest=false……
```

要点：

| 点 | 说明 |
| --- | --- |
| `permissions: contents: write` | 不写会默认只读，`gh release create` 403 |
| `gh` | ubuntu-latest 预装；`GH_TOKEN` 用 `secrets.GITHUB_TOKEN` |
| 幂等 | `gh release view` 存在 → 只 `upload --clobber`，避免重复运行报错 |
| `--verify-tag` | 防止 tag 不存在时创建错误 Release |
| `--latest=false` | 历史版本；**最后一个版本不加**，让其成为 Latest |
| 节奏 | 每个版本之间 `sleep 20`–`30`，避免同一秒刷 6 个写操作 |
| 顺序 | 从旧到新创建，最后创建最新版 |
| 资产 glob | `release-assets/<tag>/*`；README/说明不要放进去，除非要作为资产 |

---

## 4. 调试工作流（可选但强烈建议）

公开仓库的 Actions 日志在未登录网页里往往看不到；把日志**回写到一个文件**再读：

```yaml
      - name: Create or update releases
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          exec > >(tee ci-debug.txt) 2>&1
          set -x
          pwd
          git ls-files release-assets | head -40
          ls -la release-assets/v1.0.0 || true
          gh auth status || true
          gh release view v1.0.0 --json assets -q '.assets[].name' || true
          # ... create/upload ...
          gh release view v1.0.0 --json assets -q '.assets[].name' || true

      - name: Commit debug output
        if: always()
        run: |
          git config user.name "ci-debug"
          git config user.email "ci-debug@users.noreply.github.com"
          git add ci-debug.txt || true
          git commit -m "ci debug output [skip ci]" || true
          git push origin HEAD:refs/heads/ci/release-assets || true
```

要点：

- `exec > >(tee ci-debug.txt) 2>&1`：把后续所有输出同时写到文件；
- checkout 是 **detached HEAD**，回写必须 `git push origin HEAD:refs/heads/<branch>`；
- 调试提交带 `[skip ci]` 防止自我循环；
- 日志提交后，本地 `git fetch origin ci/release-assets` + `git show origin/ci/release-assets:ci-debug.txt` 读取。

---

## 5. 监控运行

```powershell
# 列出 run
$acts = (curl.exe -sL -H "User-Agent: Mozilla/5.0" "https://github.com/<owner>/<repo>/actions") -join "`n"
[regex]::Matches($acts, '/<owner>/<repo>/actions/runs/(\d+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

# 看某个 run 的状态（页面文字包含 completed success / in progress）
$rp = (curl.exe -sL -H "User-Agent: Mozilla/5.0" "https://github.com/<owner>/<repo>/actions/runs/<id>") -join "`n"
$rp -match 'completed success'
```

> 不要试图从 HTML 里抓完整日志；日志接口需要认证。用第 4 节的「日志回写」最稳。

---

## 6. 验证资产（必做，见 05 详解）

```powershell
$code = curl.exe -s -o NUL -w "%{http_code}" -I `
  "https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>"
# 302 = 存在；404 = 没传上去
```

常见「假成功」：Release 建出来了，但只有 `SHA256SUMS` 一个资产——原因就是
`.gitignore` 吞了 exe/zip，或 `git add` 没加 `-f`。

---

## 7. 清理

确认所有 Release 资产校验通过后：

```powershell
& $git switch main
& $git push origin --delete ci/release-assets
& $git branch -D ci/release-assets
& $git fetch --prune origin
```

- Release 资产在删除分支后仍然存在（Release 是独立对象）；
- 临时分支上的工作流/大文件随之从默认分支视图消失；
- 若想保留发版能力，可把工作流合并回 main 并改成手动 `workflow_dispatch`，但通常没必要。

---

## 8. 排错表

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 工作流没触发 | 提交信息含 `[skip ci]`；分支名不匹配 | 改提交信息/分支后重推 |
| run 成功但资产缺失 | 资产被 `.gitignore` 忽略 | `git add -f release-assets`，重推 |
| `gh release create` 403 | `permissions` 未写/被仓库设置降权 | 工作流加 `contents: write`；检查 Settings → Actions → Workflow permissions |
| 同一 Release 冲突 | 并发 run 同时创建 | 只推一次；用 `gh release view` 幂等保护；必要时加 `concurrency` |
| 日志里 `release already exists` 后失败 | 上传资产命令拼写错 | 用 `gh release upload`，不要用 `create` 覆盖 |
| Latest 不对 | 历史版本也创建得比最新版晚 | 最后创建最新版；或用 `gh release edit --latest` |
| 资产上传后页面看不到 | 页面缓存/懒加载 | 用下载 URL HEAD 302 验证，不要看页面 |
| run 卡住 | 某版本上传大文件慢 | 加大 timeout；检查文件是否过大（单资产 2GB 限制） |

---

## 9. 安全边界

- `GITHUB_TOKEN` 只在本次 workflow 内有效，权限由 `permissions` 限定；
- 不需要用户的 PAT、密码、2FA；
- 临时分支可被公开看到（资产本来就要公开），但工作流文件删除后不会留在 main；
- 不要把真实 token 写进 YAML/日志；`gh auth status` 会打印 `ghs_***`，日志公开仓库可见，
  必要时不要执行 `gh auth status` 或先重定向过滤。
