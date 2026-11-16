# 05 · 终极验证：仓库、标签、Release 资产

> 原则：**任何执行方（人/Agent/GPT）说「上传成功」都不算数**，必须有独立来源的机器证据。
> 本文件给出一套 5 分钟可跑完的验收流程。

---

## 1. 仓库完整性

### 1.1 refs 是否存在

```powershell
& $git fetch origin --prune
& $git ls-remote origin
```

应看到：

- `refs/heads/main`（或你的默认分支）；
- `refs/tags/<每个版本>` 以及 peel 行（annotated tag 的 `^{}`）。

### 1.2 内容级对比（最可靠）

```powershell
& $git rev-parse main^{tree}
& $git rev-parse origin/main^{tree}       # 两行必须相同
& $git diff --stat main origin/main
& $git ls-tree -r --name-only origin/main | Measure-Object -Line
```

- tree 相同 = 内容一致（即使 commit 不同）；
- 文件数应等于本地 `git ls-files | Measure-Object`；
- `git diff --stat` 非空 = 有缺失/新增，逐项检查。

### 1.3 独立 SSH 克隆（最可信）

```powershell
$tmp = "$env:TEMP\repo-check"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
& $git clone --quiet "git@github.com:<owner>/<repo>.git" $tmp
& $git -C $tmp log --oneline --decorate -3
& $git -C $tmp tag --list
& $git -C $tmp ls-files | Measure-Object
```

- 克隆成功 = SSH 认证 + 仓库可读 + 内容完整；
- 克隆后 `HEAD` 应与本地 `rev-parse HEAD` 一致（如果推的是同一历史）。

---

## 2. Release 是否存在 & 资产是否上传

### 2.1 直接下载 URL（最可靠）

GitHub Release 资产的公开下载 URL 形如：

```text
https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>
```

```powershell
$url = "https://github.com/<owner>/<repo>/releases/download/v1.0.0/app.exe"
curl.exe -s -o NUL -w "%{http_code}`n" -I -L -H "User-Agent: Mozilla/5.0" $url
```

| 状态码 | 含义 |
| --- | --- |
| `200` | 资产存在（跟随重定向后的最终状态，推荐用 `-L`） |
| `302` | 资产存在（GitHub 跳转到 release-assets CDN；未跟随时的中间状态） |
| `301` | **仓库可能被改名**（旧 URL → 新 owner/repo）；用 `-L` 跟随后再看最终 200 |
| `404` | 资产不存在 / Release 不存在 / 名字不对 |
| `403` | 仓库私有或触发限流 |

> **不要 `-L` 跟随**会得到中间 301/302；`-I -L` 只取最终响应头，不会下载文件。
> Windows 用 `-o NUL`。判定：**跟随重定向后最终 200** 才算存在。
> 仓库如果被改名，旧名的所有 URL 都会 301 到新名，这不是资产丢失。

### 2.2 批量核对本地资产目录

```powershell
$owner="<owner>"; $repo="<repo>"
Get-ChildItem "release-assets" -Directory | ForEach-Object {
  $tag = $_.Name
  Get-ChildItem $_.FullName -File | ForEach-Object {
    $u = "https://github.com/$owner/$repo/releases/download/$tag/$($_.Name)"
    $c = curl.exe -s -o NUL -w "%{http_code}" -I -H "User-Agent: Mozilla/5.0" $u
    "{0,-10} {1,-60} {2}" -f $tag, $_.Name, $c
  }
}
```

所有都是 `302` 才算通过。也可以直接用
[`scripts/verify-release-assets.ps1`](../scripts/verify-release-assets.ps1)。

### 2.3 页面内资产片段（辅助）

```powershell
$frag = (curl.exe -sL -H "User-Agent: Mozilla/5.0" `
  "https://github.com/<owner>/<repo>/releases/expanded_assets/v1.0.0") -join "`n"
[regex]::Matches($frag, '/releases/download/[^"]*?/([^"/?]+)') |
  ForEach-Object { [uri]::UnescapeDataString($_.Groups[1].Value) } | Select-Object -Unique
```

注意：Release 页面本身可能懒加载/缓存，`expanded_assets` 比页面可靠，但仍不如 2.1 的直接 HEAD。

---

## 3. Latest Release 是否正确

```powershell
$loc = curl.exe -s -o NUL -w "%{url_effective}" -I -L -H "User-Agent: Mozilla/5.0" `
  "https://github.com/<owner>/<repo>/releases/latest"
Write-Host $loc     # 应包含 /releases/tag/<最新版本>
```

> 用 `-L` 跟随；`%{url_effective}` 是最终 URL。若最终 URL 里的 owner/repo 与输入不同，
> 说明仓库被改名了——按新名字记录，并更新本地 remote/文档。

若 Latest 不对：

- 创建顺序错了（历史版本在最新版之后创建）；
- 或历史版本未加 `--latest=false`；
- 网页 Release 页面可手动改 Latest，或用 API（需 token）。

---

## 4. 资产内容校验（SHA256）

```powershell
$tmp = "$env:TEMP\asset-check.bin"
curl.exe -sL --max-time 120 -o $tmp `
  "https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>"
$actual = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
$expected = "<本地文件的哈希>"
Write-Host "match: $($actual -eq $expected)"
Remove-Item $tmp -Force
```

若 `SHA256SUMS-<tag>.txt` 也上传了，可下载它来批量核对：

```powershell
curl.exe -sL -o "$env:TEMP\SHA256SUMS.txt" `
  "https://github.com/<owner>/<repo>/releases/download/<tag>/SHA256SUMS-<tag>.txt"
Get-Content "$env:TEMP\SHA256SUMS.txt"
```

---

## 5. Actions 状态（如果用了 CI 发版）

```powershell
$acts = (curl.exe -sL -H "User-Agent: Mozilla/5.0" `
  "https://github.com/<owner>/<repo>/actions") -join "`n"
$ids = [regex]::Matches($acts, '/<owner>/<repo>/actions/runs/(\d+)') |
  ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
foreach ($id in $ids) {
  $rp = (curl.exe -sL -H "User-Agent: Mozilla/5.0" `
    "https://github.com/<owner>/<repo>/actions/runs/$id") -join "`n"
  $status = if ($rp -match 'completed success') { 'success' }
            elseif ($rp -match 'completed failure') { 'failure' }
            elseif ($rp -match 'in progress') { 'in_progress' } else { 'unknown' }
  "$id $status"
}
```

注意：`completed success` 只能证明**步骤没抛错**，不能证明资产上传成功——仍必须做第 2 节的 HEAD 校验。

---

## 6. 失败分类表

| 证据 | 结论 | 修复 |
| --- | --- | --- |
| tree 不同 / 文件数少 | 部分上传 | 按 03 force-push 完整历史 |
| tag 缺失 | tag 没推/被删 | `git push origin --tags` |
| Release 404 | Release 未创建 | 按 04 创建 |
| Release 存在但资产 404 | 资产未上传（或被 .gitignore 吞） | `git add -f` 后重跑上传 |
| 资产 302 但 SHA256 不符 | 上传了错误文件/旧版本 | 重新上传并 `--clobber` |
| Latest 指向旧版 | 创建顺序/`--latest` 问题 | 重建或手动改 Latest |
| clone 失败但网页可见 | SSH key/权限/网络 | `ssh -T` 排查（01） |
| Actions 成功但资产缺失 | 步骤里只上传了部分文件 | 看 ci-debug.txt（04 第 4 节） |

---

## 7. 一次性验收脚本

```powershell
# 建议直接调用本 skill 的脚本
powershell -ExecutionPolicy Bypass -File scripts\verify-release-assets.ps1 `
  -Repo "<owner>/<repo>" -AssetDir ".\release-assets" -CheckLatest
powershell -ExecutionPolicy Bypass -File scripts\check-ssh-github.ps1 `
  -RepoPath "." -Repo "<owner>/<repo>"
```

退出码：

- `0`：全部通过；
- 非 `0`：至少一个资产/检查失败（脚本会打印失败项）。

---

## 8. 记录证据

发布完成后，把以下内容保存到交付记录里：

- `git rev-parse HEAD` 与 `origin/main`；
- `git tag --list`；
- 每个 Release 的资产 HEAD 状态码；
- 下载校验的 SHA256；
- `/releases/latest` 跳转目标；
- Actions run id 与状态。

这样任何人（包括下一个 Agent）都能在不重新猜测的情况下复核。
