# 08 · Token / Device Flow / 网页手动：替代发版方案

> `04-release-without-token.md` 的方案（Actions + GITHUB_TOKEN）是首选。
> 但有时它不适用：仓库禁用 Actions、不需要 CI、只发 1 个 Release、或权限受限。
> 本文件对比其余方案，并给出最小权限实践。

---

## 1. 方案对比

| 方案 | 需要用户做什么 | 权限范围 | 可撤销 | 自动化 | 风险 |
| --- | --- | --- | --- | --- | --- |
| **SSH + Actions + GITHUB_TOKEN**（推荐，见 04） | 无（只需仓库存在） | 仅本次 workflow、仅该仓库 | 无需撤销 | 高 | 低 |
| **Fine-grained PAT** | 网页创建 token 并交给执行方 | 可限定单仓库/Contents | 可随时撤销 | 高 | 中（token 传递） |
| **Classic PAT** | 网页创建 token | `repo`（+`workflow`） | 可撤销 | 高 | 中高（范围大） |
| **OAuth device flow（gh）** | 浏览器输入一次性代码并授权 | 通常 `repo`、`read:org` 等 | `gh auth logout` / 网页撤销 | 高 | 中（授权范围较大） |
| **网页手动** | 手动点 6 次并拖文件 | 登录会话 | 退出登录 | 低 | 最低（但慢/易漏） |

---

## 2. Fine-grained PAT（最小权限）

### 2.1 创建

1. GitHub → Settings → Developer settings → **Personal access tokens → Fine-grained tokens** → Generate new token；
2. **Repository access**：Only select repositories → 只选目标仓库；
3. **Permissions**：
   - `Contents`: **Read and write**（git push / Release 创建与资产上传通常都够）；
   - `Metadata`: Read（自动附带）；
   - 如需推送 `.github/workflows`，可能还需要 `Workflows: Read and write`；
4. **Expiration**：最短可用（例如 7 天，甚至 1 天）；
5. 生成后只显示一次，立即复制。

### 2.2 使用（不要把 token 写进命令历史/日志）

```powershell
# 方式 A：交给 gh（一次）
$env:GH_TOKEN = "<token>"
gh release create v1.0.0 --verify-tag --title "..." --notes-file notes.md release-assets/v1.0.0/*

# 方式 B：curl 调 REST
curl.exe -s -X POST -H "Authorization: Bearer <token>" -H "Accept: application/vnd.github+json" `
  "https://api.github.com/repos/<owner>/<repo>/releases" -d "{...}"
```

- 不要 `Write-Host $token`、不要 `set -x`、不要写进仓库/日志；
- 在 Agent 环境中，最好让用户把 token 写入临时文件，程序读取后立即删除文件；
- **用完立即在 GitHub 撤销**（Settings → Developer settings → PAT → Delete）。

### 2.3 git push 用 PAT（不推荐）

```powershell
# 临时 URL（会出现在进程参数/配置中，尽量用 SSH 替代）
git push "https://<username>:<token>@github.com/<owner>/<repo>.git" main --tags
```

更安全：`http.extraHeader` 或 credential helper；但**能用 SSH 就用 SSH**。

---

## 3. OAuth device flow（gh CLI）

### 3.1 安装

- GitHub CLI 官方发布：<https://github.com/cli/cli/releases>
- Windows 也有 `winget install GitHub.cli`（若 winget 可用）。

### 3.2 登录

```powershell
gh auth login --hostname github.com --web --git-protocol ssh
```

流程：

1. 终端显示一次性代码（如 `XXXX-XXXX`）并打开浏览器；
2. 浏览器里（已登录账号）输入代码，授权；
3. 终端提示登录成功；token 存在 `gh` 的配置中（Windows 凭据管理器/`hosts.yml`）。

### 3.3 发版

```powershell
gh release create v1.0.0 --verify-tag --title "..." --notes-file notes.md release-assets/v1.0.0/*
gh release upload v1.0.0 release-assets/v1.0.0/* --clobber
```

### 3.4 结束

```powershell
gh auth logout --hostname github.com
```

- 或在 GitHub Settings → Applications → Authorized OAuth Apps 撤销「GitHub CLI」；
- device flow 的 token 权限通常比 fine-grained PAT 大，能不用就不用。

---

## 4. 网页手动（1 个 Release 时最稳）

1. 打开 `https://github.com/<owner>/<repo>/releases/new`；
2. 选择 tag（必须已存在），填 title；
3. 粘贴 notes（Markdown）；
4. 上传资产（拖拽；注意每个文件大小限制 2GB）；
5. 发布；对旧版本勾选「Set as a pre-release」不需要，Latest 由创建顺序/手动设置；
6. 用 05 的 HEAD 302 方法逐个校验。

优点：零 token、零自动化；缺点：多个版本时容易漏/慢。

---

## 5. 选择建议

```text
需要批量发多个 Release？
├─ 能推 CI 分支 → 04（Actions，最推荐）
├─ 不能推 CI 但能授权一次 → fine-grained PAT（最小权限，用完撤销）
├─ 只有 1 个 Release → 网页手动
└─ 不想碰 token 也不想 CI → 让用户手动（提供文件清单 + 校验步骤）
```

---

## 6. 安全红线

- **永远不要**把 GitHub 密码、2FA 验证码、长期 PAT 发给任何第三方（包括 AI）；
- **不要**把 token 写进仓库、README、Issue、日志、聊天记录；
- 优先 fine-grained 而非 classic；优先单仓库而非全账号；
- 任务完成后**检查 token 是否撤销**；
- 如果 token 曾以明文出现在公开位置：立即撤销并重新生成。
