# 08 · 创建仓库 / gh CLI 授权 / Token / Device Flow

> 关键前提：**SSH key 只能认证 git 协议，不能创建仓库，也不能调用 REST API。**
> 新建 GitHub 仓库必须走 **网页 / REST API / GitHub CLI（device flow）** 三者之一。
>
> 本文覆盖：
> 1. Windows 无管理员安装 gh CLI；
> 2. `gh auth login` 的 **OAuth device flow**（本案例实际使用的方法）；
> 3. 用 gh 创建仓库 + 设置 topics，再用 SSH 推送；
> 4. Fine-grained PAT / classic PAT / 网页手动 的对比与最小权限实践。

---

## 1. 方案对比

| 方案 | 能建仓库 | 需要用户做什么 | 权限范围 | 可撤销 | 自动化 | 风险 |
| --- | --- | --- | --- | --- | --- | --- |
| **gh CLI + device flow + SSH push**（推荐用于建仓） | ✅ | 浏览器授权一次 | `repo` 等（gh OAuth App） | `gh auth logout` / 网页撤销 | 高 | 中（授权范围较大） |
| **Fine-grained PAT** | ✅（权限够时） | 网页创建 token 并交给执行方 | 可限定单仓库/Contents | 可随时撤销 | 高 | 中（token 传递） |
| **Classic PAT** | ✅ | 网页创建 token | `repo`（+`workflow`） | 可撤销 | 高 | 中高（范围大） |
| **网页手动** | ✅ | 点「New repository」+ 填表 | 登录会话 | 退出登录 | 低 | 最低（但慢） |
| **SSH** | ❌ | — | — | — | — | — |

> 本案例实际路径：Windows 安装便携 gh → device flow 授权 → `gh repo create` 建仓 →
> `gh repo edit` 设 topics → `git push` 走 SSH → `gh auth logout` 删除 token。

---

## 2. Windows 无管理员安装 gh CLI

```powershell
# 2.1 找最新版本（latest 会 302 到具体 tag）
$loc = (curl.exe -sIL -H "User-Agent: Mozilla/5.0" `
  "https://github.com/cli/cli/releases/latest") |
  Select-String -Pattern '^location:' | Select-Object -Last 1
$tag = ($loc -split '/tag/')[-1].Trim()      # 例如 v2.104.0
$ver = $tag.TrimStart('v')                   # 2.104.0

# 2.2 下载 Windows amd64 zip
$url = "https://github.com/cli/cli/releases/download/$tag/gh_${ver}_windows_amd64.zip"
$zip = "$env:TEMP\gh-cli.zip"
curl.exe -sL --retry 3 --max-time 300 -o $zip $url
if ((Get-Item $zip).Length -lt 5MB) { throw "gh 下载不完整" }

# 2.3 解压到用户目录（zip 内是 bin/gh.exe + share/...）
$extract = "$env:TEMP\gh-extract"
Expand-Archive $zip $extract -Force
$dest = "$env:LOCALAPPDATA\Programs\gh"
New-Item -ItemType Directory -Force -Path "$dest\bin" | Out-Null
Copy-Item (Join-Path $extract "bin\gh.exe") "$dest\bin\gh.exe" -Force

# 2.4 用户级 PATH
$userPath = [Environment]::GetEnvironmentVariable('Path','User')
if ($userPath -notlike "*$dest\bin*") {
  [Environment]::SetEnvironmentVariable('Path', "$dest\bin;$userPath", 'User')
}
& "$dest\bin\gh.exe" --version
```

> 与 OpenSSH 一样：用户级 PATH 只对**新进程**生效；当前 Agent 进程里请用绝对路径，
> 或临时 `$env:Path = "$dest\bin;$env:Path"`。

---

## 3. gh CLI 的 OAuth device flow（本案例实际用法）

### 3.1 命令

```powershell
$gh = "$env:LOCALAPPDATA\Programs\gh\bin\gh.exe"
$env:PATH = "$env:LOCALAPPDATA\Programs\gh\bin;$env:PATH"

gh auth login --hostname github.com --git-protocol ssh --web --insecure-storage
```

- `--web`：使用 **OAuth device flow**（浏览器授权，不是密码登录）；
- `--git-protocol ssh`：授权后 git 操作走 SSH（不会配置 HTTPS 凭据）；
- `--insecure-storage`：token 存到 `%APPDATA%\GitHub CLI\hosts.yml`（明文）。
  不加则尝试系统密钥环；在无桌面/受限环境里 keyring 可能失败。**用完记得 logout**。

### 3.2 终端会看到什么

```text
! One-time code (3310-88E3) copied to clipboard
Open this URL to continue in your web browser: https://github.com/login/device
```

1. 打开 <https://github.com/login/device>（已登录目标账号）；
2. 输入一次性代码（新版本已自动复制到剪贴板）；
3. 点 **Authorize** 授权「GitHub CLI」；
4. 终端里的 `gh auth login` 自动完成，退出码 0。

### 3.3 非交互 / Agent 环境技巧

`gh auth login` 会等一句 `Press Enter to open ...`，Agent 里没有 TTY 时用管道送一个空行：

```powershell
cmd.exe /c "echo. | `"$gh`" auth login --hostname github.com --git-protocol ssh --web --insecure-storage"
```

在 Agent 中建议：

1. 用**后台任务**启动上面的命令；
2. 隔几秒读任务输出，抓取 `One-time code (XXXX-XXXX)` 与 `https://github.com/login/device`；
3. 把代码/URL 展示给用户，请其授权（可用交互式提问工具阻塞等待）；
4. 用户确认后 `gh auth status` 验证，再继续建仓/推送。

### 3.4 验证

```powershell
gh auth status
```

本案例实际输出：

```text
github.com
  ✓ Logged in to github.com account QSH2 (...\GitHub CLI\hosts.yml)
  - Active account: true
  - Git operations protocol: ssh
  - Token: gho_************************************
  - Token scopes: 'gist', 'read:org', 'repo'
```

> `gho_` 是 GitHub CLI OAuth App 的 token；scopes 通常包含 `repo`、`read:org`、`gist`。
> 足够创建仓库、改 topics、管理 Release；**不要**把它打印到公开日志。

---

## 4. 用 gh 创建仓库，再用 SSH 推送

### 4.1 创建空仓库

```powershell
$gh = "$env:LOCALAPPDATA\Programs\gh\bin\gh.exe"
gh repo create "<owner>/<repo>" --public `
  --description "给 AI Agent 的 GitHub 安全发布技能包：SSH 推送、Actions 发 Release、残缺仓库修复、发布校验与防风控。"
```

- 成功后输出仓库 URL；
- 新仓库是空的：`defaultBranchRef.name` 为空，**还没有默认分支**；
- 建完不要立刻批量再建第二个（新账号 + 高频建仓是风控特征）。

### 4.2 设置 Topics

```powershell
gh repo edit "<owner>/<repo>" `
  --add-topic ai-agent `
  --add-topic skill `
  --add-topic github `
  --add-topic ssh `
  --add-topic release `
  --add-topic github-actions `
  --add-topic powershell `
  --add-topic automation `
  --add-topic devtools `
  --add-topic agent-skills
```

### 4.3 用 SSH 推送本地仓库

```powershell
cd <local-repo>
git remote add origin "git@github.com:<owner>/<repo>.git"
git push -u origin main
git tag -a v1.0.0 -m "v1.0.0 — initial release"
git push origin --tags
```

- 建仓用 gh，推送用 SSH：两者互不冲突；
- 第一次 push 后默认分支自动变成 `main`；
- 验证：`git ls-remote --heads --tags origin`、独立 clone、tree 对比（见 05）。

### 4.4 结束：删除本地 token

```powershell
gh auth logout --hostname github.com
```

- 删除 `hosts.yml` 里的 token；
- 如需彻底撤销：GitHub Settings → Applications → Authorized OAuth Apps →
  撤销「GitHub CLI」；
- 之后 `gh auth status` 会提示未登录（本案例就是这样收尾的）。

---

## 5. Fine-grained PAT（最小权限，适合 CI/长期自动化）

### 5.1 创建

1. GitHub → Settings → Developer settings → **Personal access tokens → Fine-grained tokens** → Generate new token；
2. **Repository access**：Only select repositories → 只选目标仓库；
3. **Permissions**：
   - `Contents`: **Read and write**（git push / Release 创建与资产上传通常都够）；
   - `Metadata`: Read（自动附带）；
   - 如需推送 `.github/workflows`，可能还需要 `Workflows: Read and write`；
   - 如需创建仓库：`Administration: Read and write`（或使用 classic `repo`）；
4. **Expiration**：最短可用（例如 7 天，甚至 1 天）；
5. 生成后只显示一次，立即复制。

### 5.2 使用（不要把 token 写进命令历史/日志）

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

### 5.3 git push 用 PAT（不推荐）

```powershell
# 临时 URL（会出现在进程参数/配置中，尽量用 SSH 替代）
git push "https://<username>:<token>@github.com/<owner>/<repo>.git" main --tags
```

更安全：`http.extraHeader` 或 credential helper；但**能用 SSH 就用 SSH**。

---

## 6. 网页手动创建仓库（零 token，最稳）

1. 打开 `https://github.com/new`；
2. 填 Repository name、Description，选 Public/Private；
3. **不要**勾选 "Add a README file"（保持空仓库，方便本地首推）；
4. 点 **Create repository**；
5. 之后用 SSH 推送（第 4.3 节）；
6. 网页 About 齿轮里补 Topics。

适合：只需要建一个仓库、或 agent 环境不方便跑 gh。

---

## 7. 选择建议

```text
要做什么？
├─ 只是新建一个仓库并推送
│   ├─ 有 gh 且能浏览器授权 → gh device flow + gh repo create + SSH push（推荐）
│   ├─ 不能跑 gh → 网页手动建空仓库 + SSH push
│   └─ 有现成 PAT → gh repo create（GH_TOKEN=...）+ SSH push
├─ 批量发多个 Release
│   ├─ 能推 CI 分支 → references/04（Actions，最推荐）
│   ├─ 不能推 CI 但能授权一次 → fine-grained PAT（最小权限，用完撤销）
│   └─ 只有 1 个 Release → 网页手动，按 05 校验
└─ 只想改 topics/描述 → gh repo edit 或网页 About 齿轮
```

---

## 8. 安全红线

- **永远不要**把 GitHub 密码、2FA 验证码、长期 PAT 发给任何第三方（包括 AI）；
- **不要**把 token 写进仓库、README、Issue、日志、聊天记录；
- `gh auth login --insecure-storage` 的 token 是**明文**，任务完成必须 `gh auth logout`；
- 优先 fine-grained 而非 classic；优先单仓库而非全账号；
- 任务完成后**检查 token 是否撤销**（`gh auth status` / 网页 Authorized OAuth Apps）；
- 如果 token 曾以明文出现在公开位置：立即撤销并重新生成。

---

## 9. 排错表

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `gh auth login` 卡在 `Press Enter` | 无 TTY，没送 Enter | `cmd /c "echo. \| gh auth login ..."` |
| 看不到一次性代码 | gh 版本/输出被缓冲 | 用后台任务读取输出；或先 `gh auth status` 看是否已登录 |
| 浏览器没打开 | 环境无默认浏览器/被拦截 | 手动打开 <https://github.com/login/device>，代码在终端/剪贴板 |
| `gh repo create` 报 admin 权限不足 | PAT 缺建仓权限 | 用 gh OAuth（`repo`）或加 `Administration` 权限 |
| 建完 `defaultBranchRef.name` 为空 | 仓库还没有提交 | 正常，push 后自动出现 `main` |
| `gh auth status` 显示未登录但 push 成功 | push 走的是 SSH，与 gh token 无关 | 正常；gh token 只用于 API |
| 想复用同一 token 多次任务 | token 生命周期/风控 | 每次任务重新 device flow，结束 logout |
