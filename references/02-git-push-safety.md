# 02 · 安全 git push 与历史/作者改写

> 目标：把本地仓库安全推到 GitHub，覆盖远端前有备份、有对比、有回退。
> 适用：首次推送、强制覆盖、换账号后改写作者、推 tag。

---

## 1. 推送前：备份与体检

```powershell
$git = (Get-Command git).Source

# 1.1 完整备份（含所有 refs/tags），这是 force push / 历史改写的唯一保险
& $git bundle create "E:\backups\pre-push-$(Get-Date -Format yyyyMMdd-HHmm).bundle" --all
& $git bundle verify "E:\backups\pre-push-*.bundle"   # 应显示 "records a complete history"

# 1.2 本地状态
& $git status -sb
& $git log --oneline --decorate -10
& $git tag --list

# 1.3 远端可达性（SSH）
& $git ls-remote origin
```

---

## 2. 首次推送：先 main，再 tags

```powershell
& $git push -u origin main
Start-Sleep -Seconds 60          # 新账号/大仓库建议停 1–2 分钟
& $git push origin --tags
& $git ls-remote --heads --tags origin
```

为什么分开：

- 一次 push 同时刷 main + 大量 tag 更像「批量写」，新账号更容易被风控；
- 出错时能清楚区分是分支还是 tag 的问题；
- tag 推送成功后立即用 `ls-remote` 核对。

---

## 3. 远端已有内容：先对比，再决定 force

```powershell
& $git fetch origin --prune
& $git rev-parse main^{tree}
& $git rev-parse origin/main^{tree}          # 相等 = 内容一致
& $git diff --stat main origin/main
& $git ls-tree -r --name-only origin/main | Measure-Object    # 远端文件数
& $git log --oneline -5 origin/main
```

决策表：

| 远端状态 | 动作 |
| --- | --- |
| 空仓库（无 main） | 直接 `push -u origin main` |
| 内容一致，只是 commit 不同（如网页/他人导入） | 保留旧 HEAD 为 `backup/...` 分支，再 `--force-with-lease` 覆盖 |
| 远端是本地内容子集（网页上传缺目录） | 同上；先确认没有唯一文件 |
| 远端有本地没有的提交/文件 | **不要 force**；先 fetch 对比、合并或询问用户 |
| 远端 default branch 是别的名字 | 先确认再推；必要时 `git push -u origin main` 后改默认分支 |

安全覆盖标准流程：

```powershell
# 1) 旧远端 HEAD 保留成备份分支（可随时恢复）
& $git push origin "<oldsha>:refs/heads/backup/web-upload"

# 2) 必须 fetch 过，--force-with-lease 才安全
& $git fetch origin
& $git push --force-with-lease origin main

# 3) 再推 tags
& $git push origin --tags
```

- **永远不要用 `git push --force`**（无 lease 保护，可能覆盖别人刚推的提交）。
- 覆盖后验证：`git ls-remote`、独立 clone、tree 对比（见 05）。

---

## 4. 历史/作者改写（换 GitHub 账号后）

场景：旧账号的提交作者是 `OldName <old@example>`，新仓库要显示 `NewName <new@users.noreply.github.com>`。

### 4.1 准备

- 先做 bundle 备份（第 1 节）。
- 确认新身份：GitHub username、user id（可从个人页 HTML 的 `avatars.githubusercontent.com/u/<id>` 取）；
  noreply 邮箱 = `<id>+<username>@users.noreply.github.com`。
- 工作区干净：`git status` 必须为空。

### 4.2 commit-tree 重建（推荐，保留日期与消息）

```powershell
$git = "C:\path\to\git.exe"
$newName  = 'NewName'
$newEmail = '123456+NewName@users.noreply.github.com'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$tmp = Join-Path $env:TEMP ("msg-" + [guid]::NewGuid().ToString('N') + ".txt")

$commits = & $git rev-list --reverse main
$map = @{}
foreach ($c in $commits) {
  $tree   = (& $git rev-parse "$c^{tree}").Trim()
  $parent = (& $git log -1 --format='%P' $c).Trim()
  $msg    = (& $git log -1 --format='%B' $c) -join "`n"
  $msg    = $msg.TrimStart([char]0xFEFF).TrimEnd("`r","`n") + "`n"
  [System.IO.File]::WriteAllText($tmp, $msg, $utf8NoBom)   # 关键：无 BOM 文件 + -F

  $env:GIT_AUTHOR_NAME = $newName;  $env:GIT_AUTHOR_EMAIL = $newEmail
  $env:GIT_COMMITTER_NAME = $newName; $env:GIT_COMMITTER_EMAIL = $newEmail
  $env:GIT_AUTHOR_DATE = (& $git log -1 --format='%aI' $c).Trim()
  $env:GIT_COMMITTER_DATE = (& $git log -1 --format='%cI' $c).Trim()

  $parentArgs = @()
  if ($parent) { $parentArgs = @('-p', $map[$parent]) }
  $map[$c] = (& $git commit-tree $tree @parentArgs -F $tmp).Trim()
}

& $git update-ref refs/heads/main $map[($commits[-1])]
```

### 4.3 tag 重建

```powershell
foreach ($t in (& $git tag --list)) {
  $oldTarget = (& $git rev-list -n 1 "refs/tags/$t").Trim()
  $newTarget = $map[$oldTarget]
  if (-not $newTarget) { continue }

  $msg = (& $git tag -l --format='%(contents)' $t) -join "`n"
  $msg = $msg.TrimStart([char]0xFEFF).TrimEnd("`r","`n") + "`n"
  [System.IO.File]::WriteAllText($tmp, $msg, $utf8NoBom)

  $taggerDate = (& $git for-each-ref --format='%(taggerdate:iso-strict)' "refs/tags/$t").Trim()
  & $git tag -d $t | Out-Null
  $env:GIT_COMMITTER_DATE = $taggerDate
  & $git tag -a $t $newTarget -F $tmp | Out-Null
}
Remove-Item $tmp -Force
& $git reset --hard main
```

### 4.4 已知坑（血泪）

| 坑 | 现象 | 解法 |
| --- | --- | --- |
| PowerShell 管道给 `git commit-tree` | 每条提交消息开头多一个不可见 BOM（`\uFEFF`） | 用 `-F <file>`，文件用 `UTF8Encoding($false)` 写 |
| `Get-Content` 读 UTF-8 文档 | 中文变乱码（PS 5.1 默认 ANSI） | `-Encoding UTF8` |
| 用 `-replace` 改源码文件 | 可能写出非法 UTF-8 / 破坏中文 | 用编辑器/write 工具，不要用 PowerShell 正则改源码 |
| tag 未重建 | 新提交与旧 tag 不匹配，Release 指向旧对象 | 按 4.3 重建，`git ls-remote --tags` 核对 |
| 改写后忘记 reset | 工作区/索引仍指向旧 HEAD | `git reset --hard main` |
| 没备份就改写 | 无法回退 | 先 `git bundle create --all` |

### 4.5 验证

```powershell
& $git log --format="%h | %an <%ae> | %s" -10
& $git tag --list
& $git cat-file commit HEAD   # 第一行应以 "tree " 开头（不是 BOM）
```

---

## 5. 推送 `.github/workflows` 的注意点

- **SSH 推送** workflow 文件通常可以（本案例实测可推）；
- **HTTPS + OAuth token** 推送 workflow 文件需要 `workflow` scope，否则被拒绝；
- 如果 push 报 `refusing to allow a Personal Access Token to create or update workflow`，
  换 SSH 或给 token 加 `workflow` 权限。

---

## 6. 推送后立即做

1. `git ls-remote origin` 核对 refs；
2. 独立 clone（见 05）；
3. 若是覆盖推送，确认备份分支存在；
4. 更新文档里所有旧仓库名/旧账号链接（`rg -n "old-name|old-owner"`）。
