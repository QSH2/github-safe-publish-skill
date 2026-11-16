---
name: github-safe-publish
description: >
  安全地把本地仓库发布到 GitHub 的完整方法：Windows 无管理员安装 OpenSSH、生成并接入 SSH key、
  分离式 git push（先 main 后 tags）、仓库改名/网页残缺上传修复、不暴露 token 地用 GitHub
  Actions 官方 GITHUB_TOKEN 创建 Release 并上传资产、逐项验证（独立 SSH 克隆 / tree 对比 /
  资产下载 HEAD 跟随重定向 / SHA256），以及新账号被风控 suspended 的预防与申诉。
  触发词：GitHub 上传、SSH 推送、SSH 配置、Release 发布、发版、仓库改名、网页上传缺文件、
  GitHub 封禁/suspended、Actions 发版、release 资产、git push 失败、github 风控。
author: 清水Shimizu-github@QSH2 与她的 deepseek
---

# GitHub 安全发布（SSH + Actions）

> 来源：一次真实事故与修复。原账号在「新注册 + 约 20 分钟内批量建仓/发 Release」后被
> GitHub 风控 suspended；随后用本流程在一个新账号上完成：完整 Git 历史 SSH 推送、6 个
> Release 的资产上传、逐项校验，并且**没有使用用户密码、没有手动 token、没有网页自动化**。
>
> 渐进式披露：本文档只是目录与决策树，细节在 `references/` 下按主题分文件。
> 先读「决策树」和「30 秒速查」，再只打开你需要的那一个 reference，节省上下文。

---

## 能力边界（先读）

| 目标 | SSH 能做 | 不能做 |
| --- | --- | --- |
| 推送提交 / 分支 / tag | ✅ `git push` | — |
| **创建新仓库** | ❌ | 需要 **网页 / REST API / gh CLI device flow**（见 08） |
| 创建/更新 Release | ❌ | 需要 **网页 / REST API / GitHub Actions 内的 GITHUB_TOKEN** |
| 上传 Release 资产 | ❌ | 同上 |
| 修改仓库 Topics / 描述 | ❌ | 网页、`gh repo edit` 或 API |
| 验证远端内容 | ✅ 克隆、`ls-remote`、tree 对比 | Release 资产需 HTTP HEAD/下载校验 |

> 关键认知：**SSH key 只认证 git 协议，不能调用 REST API，也不能创建仓库**。
> 建仓走 `references/08`，发 Release 走 `references/04`，不要在这两件事上找 SSH 的办法。

---

## 目录（按需阅读）

| # | 文件 | 覆盖内容 | 何时读 |
|---|---|---|---|
| 01 | [`references/01-ssh-windows-setup.md`](references/01-ssh-windows-setup.md) | Windows 无管理员装便携 OpenSSH、`ssh-keygen` 空口令坑、known_hosts 指纹校验、`~/.ssh/config`、把公钥加到 GitHub、`ssh -T` 验证 | 第一次在这台机器配 GitHub SSH |
| 02 | [`references/02-git-push-safety.md`](references/02-git-push-safety.md) | 推送前备份 bundle、先 main 后 tags、`--force-with-lease`、备份旧远端为分支、作者/历史改写（commit-tree + tag 重建）、UTF-8 BOM 坑 | 要把本地历史推上去/覆盖远端 |
| 03 | [`references/03-repo-repair-and-rename.md`](references/03-repo-repair-and-rename.md) | 识别网页上传残缺（只有顶层文件、单 commit "Add files via upload"）、tree 对比、改名后同步 remote、force 推送、保留旧内容分支 | 远端仓库不完整或刚改名 |
| 04 | [`references/04-release-without-token.md`](references/04-release-without-token.md) | **临时 Actions 工作流发 Release**：资产分支、`.gitignore` 吞 exe/zip 的强制 add、权限、`gh release create/upload --clobber`、幂等、节奏、把调试日志 commit 回分支、清理 | 没有 PAT、又不想网页点 6 次 |
| 05 | [`references/05-verification.md`](references/05-verification.md) | 终极校验：独立 SSH 克隆、tree/file 数、`ls-remote`；Release 资产 HEAD（跟随重定向，最终 200）、`expanded_assets`、`/releases/latest` 跳转、SHA256 下载核对、Actions 状态 | 每次发布后 |
| 06 | [`references/06-anti-suspension.md`](references/06-anti-suspension.md) | GitHub 风控/封号规律、被 suspended 的症状（API 403 原文）、申诉入口与 6 个月窗口、预防清单、token 卫生 | 新账号/批量操作前；或已被封 |
| 07 | [`references/07-case-study-pcl-rp.md`](references/07-case-study-pcl-rp.md) | 本次完整时间线复盘：老号被封 → 新号 QSH2 → GPT 网页只传了 8 个文件 → SSH 补全 → Actions 发 6 个 Release → 校验 | 想看重现案例与真实踩坑顺序 |
| 08 | [`references/08-token-and-device-flow.md`](references/08-token-and-device-flow.md) | **创建仓库 + gh CLI 授权**：Windows 便携 gh、OAuth device flow（含非交互式调用）、`gh repo create`/topics、SSH 推送、logout；PAT/网页手动对比 | 要新建仓库、或 Actions 方案不适用时 |

**脚本与模板**

| 路径 | 用途 |
| --- | --- |
| [`scripts/check-ssh-github.ps1`](scripts/check-ssh-github.ps1) | 只读检查：SSH 连通性、远端 HEAD/tree 与本地是否一致、tag 列表 |
| [`scripts/verify-release-assets.ps1`](scripts/verify-release-assets.ps1) | 按本地资产目录逐项 HEAD 校验 Release 资产（跟随重定向，最终 200/404）、latest 跳转、可选 SHA256 |
| [`scripts/make-release-workflow.ps1`](scripts/make-release-workflow.ps1) | 由 JSON 清单生成临时 Actions 发版工作流（含 title/notes/assets/latest 规则） |
| [`scripts/push-main-then-tags.ps1`](scripts/push-main-then-tags.ps1) | 安全推送：先 main、等待、再 tags；可选自动 bundle 备份与 dry-run |
| [`assets/create-releases.yml.template`](assets/create-releases.yml.template) | Actions 工作流模板（`gh release create/upload` + 调试日志回写） |
| [`assets/release-manifest.example.json`](assets/release-manifest.example.json) | 发版清单示例（tag/title/assets/notes/latest） |

---

## 决策树

```
你要做什么？
├─ 这台 Windows 还没配 GitHub SSH
│   → references/01（便携 OpenSSH + ed25519 + 公钥加到 GitHub + 验证）
├─ 要在 GitHub 上新建一个仓库
│   → references/08（gh CLI device flow 建仓 + topics，再 SSH 推送）
├─ 有本地仓库要首次推到 GitHub
│   → references/02（bundle 备份 → push main → push tags）
├─ 远端仓库内容残缺 / 刚改名 / 历史不对
│   → references/03（先对比 tree，再决定 force；保留旧内容分支）
├─ 要把版本发布成 GitHub Release（要上传 exe/zip 资产）
│   ├─ 不想给任何 token → references/04（SSH 推临时分支 + Actions GITHUB_TOKEN）
│   ├─ 可以授权一次 → references/08（device flow / fine-grained PAT）
│   └─ 数量少（1 个）→ 网页手动也可以，但按 05 校验
├─ 发布完了要验收
│   → references/05（clone、tree、HEAD 302、SHA256、latest）
├─ 账号被 suspended / 怀疑被风控
│   → references/06（先查邮箱与申诉，不要开新号绕）
└─ 想复盘这次真实事故
    → references/07
```

---

## 30 秒速查（最高频的坑）

1. **Windows 没 `ssh` 且无管理员**：装微软 `Win32-OpenSSH` 便携包到 `%LOCALAPPDATA%\Programs\OpenSSH`，加**用户级 PATH**；不要用 MinGit 的 `ssh`——它没有 `ssh-keygen.exe`。
2. **`ssh-keygen -N ""` 在 PowerShell 5.1 会弹交互**：用 `.bat` + `cmd /c` 传空引号，或用 `-N ""` 的 cmd 批处理；事后用 `ssh-keygen -y -f key < NUL` 验证无口令。
3. **`GIT_SSH_COMMAND` 用反斜杠会被 shell 吃掉**：改用 `git config --global core.sshCommand "C:/.../ssh.exe"`（正斜杠）。
4. **主机指纹必须核对**：GitHub ED25519 = `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`；`ssh-keyscan` 在代理环境可能失败，可用已存在 `known_hosts` 或查官方文档。
5. **先推 main，再推 tags**，中间停 1–2 分钟；不要一条命令同时刷大量 ref。
6. **force 之前**：`git fetch`、备份 `git bundle create --all`、把远端旧 HEAD 保留成 `backup/...` 分支、用 `--force-with-lease`。
7. **网页「上传成功」不可信**：单 commit `Add files via upload` 往往漏掉整个目录；用 `git rev-parse main^{tree}` vs `origin/main^{tree}` + 文件数验证。
8. **`.gitignore` 常含 `*.exe`/`*.zip`**：发版资产提交到临时分支时要 `git add -f release-assets`，否则 Release 只有校验和文件。
9. **`[skip ci]` 会跳过工作流**：需要触发 CI 的 commit 不要带；只有工作流回写调试日志的自动 commit 才加。
10. **Actions checkout 是 detached HEAD**：回写分支要 `git push origin HEAD:refs/heads/<branch>`。
11. **Release 资产是否存在**：用 `curl -I -L` 跟随重定向，**最终 200** 才是存在；`404` 是缺失，
    `301` 通常只是仓库改名（旧 URL → 新 URL），不要误判为资产丢失。Release 页面/`expanded_assets`
    有缓存与懒加载，不可靠。
12. **私钥永远不外发**；只把 `*.pub` 加到 GitHub；任何 token 不打印、不写入仓库，用完撤销。
13. **SSH 不能创建仓库**：用 gh CLI 的 device flow（`gh auth login --web`）→ `gh repo create` →
    `gh repo edit --add-topic` → SSH 推送；结束 `gh auth logout` 删除 token（详见 08）。

---

## 铁律（安全 / 风控）

1. **新账号不要短时间批量 API 写操作**（建仓、5+ Release、上传多资产）；这是实测触发 suspended 的路径。
2. **推送/发版分离节奏**：main → tags → 每个 Release 间隔 20–30 秒以上；能分天就分天。
3. **优先用 GitHub 自己的 token**（Actions 的 `GITHUB_TOKEN`）完成 CI 内发版；不要为了省事让用户粘贴长期 token。
4. **任何"上传完成"的说法都必须用机器可验证证据**（tree / 跟随重定向的最终 200 / SHA256），不要信自然语言汇报。
5. **不把官方/第三方二进制、密钥、日志提交进公开仓库**；发版资产只走 Release。
6. **临时分支用完删除**：`git push origin --delete <tmp-branch>`，否则仓库里留下工作流和大文件。

---

## 最小验收清单（复制执行）

```powershell
# 1) 仓库完整性与历史
git ls-remote origin
git fetch origin
git rev-parse main^{tree}; git rev-parse origin/main^{tree}   # 应相等
git ls-tree -r --name-only origin/main | Measure-Object        # 与本地文件数一致

# 2) 独立克隆（最可靠）
git clone --quiet git@github.com:<owner>/<repo>.git "$env:TEMP\repo-check"
git -C "$env:TEMP\repo-check" log --oneline -1
git -C "$env:TEMP\repo-check" tag --list

# 3) Release 资产（跟随重定向，最终 200 才是存在）
curl.exe -s -o NUL -w "%{http_code}`n" -I -L "https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>"
curl.exe -s -o NUL -w "%{url_effective}`n" -I -L "https://github.com/<owner>/<repo>/releases/latest"
```

> 本次真实事故里，几乎每个坑都属于「工具说成功，但实际没上去」。本 skill 的核心就是
> **每一步都用独立来源验证**，而不是相信执行方（人或 Agent）的汇报。
