# 03 · 远端残缺修复、仓库改名与远端同步

> 目标：识别「看起来上传成功、实际缺文件」的仓库，修复它；并正确处理仓库改名后的 remote 同步。

---

## 1. 识别残缺上传（最常见的假成功）

症状：

- 远端只有一个提交：`Add files via upload` / `Initial commit`；
- 只出现顶层文件（README/LICENSE/.gitignore 等），整个 `src/`、`docs/`、`.github/` 不见了；
- 文件数远少于本地。

```powershell
& $git fetch origin --prune
& $git log --oneline -5 origin/main
& $git ls-tree -r --name-only origin/main
& $git ls-tree -r --name-only origin/main | Measure-Object

# 最关键：tree 对比（内容级，不受 commit 历史影响）
& $git rev-parse main^{tree}
& $git rev-parse origin/main^{tree}
& $git diff --stat main origin/main
```

判断：

| 现象 | 结论 |
| --- | --- |
| tree 相同 | 内容完整，只是历史不同 |
| 远端是本地子集（`git diff` 全是删除本地文件） | 网页/工具漏传目录 |
| 远端文件数 < 本地 | 残缺，需要重新推送 |
| 远端有本地没有的文件 | 先取回/合并，禁止直接 force |

> 「上传成功」是执行方的自述；**tree 哈希与文件数是唯一可信证据**。

---

## 2. 修复残缺仓库（SSH 覆盖）

```powershell
# 2.1 备份远端旧 HEAD 为分支（保留证据/可回滚）
& $git fetch origin
$old = (& $git rev-parse origin/main).Trim()
& $git push origin "${old}:refs/heads/backup/web-upload"

# 2.2 确认本地完整 & 工作区干净
& $git status -sb

# 2.3 覆盖 main（先 fetch 过才安全）
& $git push --force-with-lease origin main

# 2.4 推 tags
& $git push origin --tags
```

修复后验证（必须）：

```powershell
& $git ls-remote origin
& $git rev-parse main^{tree}; & $git rev-parse origin/main^{tree}   # 应相等
# 独立克隆（最可靠）
& $git clone --quiet git@github.com:<owner>/<repo>.git "$env:TEMP\repo-check"
& $git -C "$env:TEMP\repo-check" ls-files | Measure-Object
& $git -C "$env:TEMP\repo-check" tag --list
```

确认无误后再删除备份分支（可选）：

```powershell
& $git push origin --delete backup/web-upload
```

---

## 3. 仓库改名后的同步

GitHub 改名后：

- 网页会自动跳转旧 URL；
- **git remote 不会自动更新**，仍是旧 URL（GitHub 会 301，但依赖跳转不可靠，尤其是 CI/镜像）；
- 本地文档、README、发布页里的 clone 地址仍然是旧的。

### 3.1 更新 remote

```powershell
& $git remote -v
& $git remote set-url origin git@github.com:<owner>/<new-name>.git
& $git ls-remote origin          # 必须能列出 refs
& $git fetch origin --prune
& $git branch -u origin/main main
```

> 改名后旧 URL 通常返回 **301** 到新 URL（网页与下载链接都是）。Git 一般能自动跟随，
> 但 CI、脚本、文档里的旧 URL 会留下隐患；验证脚本必须跟随重定向后再判定（见 05）。
> 如果 `ls-remote` 仍成功但 `git remote -v` 还是旧名，说明只是 GitHub 在帮你跳转，
> 不代表 remote 已更新。

### 3.2 全仓库搜索旧名/旧账号

```powershell
# 用 ripgrep（或 git grep）
rg -n "old-repo-name|old-owner|old-account" --glob '!**/bin/**' --glob '!**/obj/**'
```

需要同步的位置通常有：

- README / README.en 的标题、clone 命令、release 下载链接；
- 打包脚本、CI workflow 中的仓库名；
- 发布包文档（上传说明、给上传者的指令）；
- GUI/程序内的「GitHub 链接」、关于页、版本信息；
- 本地 Git remote、`.gitmodules`（若有 submodule）。

### 3.3 若改名同时换了账号

- 旧账号的 remote 可能已失效（账号 suspended/删除）；
- 先确认新 remote 可达：`git ls-remote git@github.com:<new-owner>/<repo>.git`；
- 作者改写见 02 第 4 节；
- 旧账号的 Issue/PR/Release 不会自动迁移；
- 旧仓库备份分支（如 `backup/web-upload`）按需保留或删除。

---

## 4. 远端同步的只读检查清单

```powershell
# remote 是否指向预期
& $git remote -v

# 默认分支
& $git ls-remote --symref origin HEAD

# 所有分支/tag
& $git ls-remote --heads --tags origin

# 本地 vs 远端
& $git status -sb
& $git rev-list --left-right --count main...origin/main

# 远端文件清单
& $git ls-tree -r --name-only origin/main
```

---

## 5. 常见错误与处理

| 错误 | 原因 | 处理 |
| --- | --- | --- |
| `fatal: repository not found` | 改名/改 owner 后 remote 未更新；或私钥无权 | 更新 remote；`ssh -T` 验证账号 |
| `! [rejected] main -> main (fetch first)` | 远端有新提交 | 先 fetch 对比；不要直接 force |
| `! [rejected] ... (stale info)` | `--force-with-lease` 的 lease 过期 | 重新 fetch 后再 force |
| 推 tags 报 already exists but different | tag 指向旧 commit | 确认后 `git push --force origin <tag>`（谨慎）或删除远端 tag 重推 |
| 推 workflow 文件被拒 | HTTPS token 缺 `workflow` scope | 换 SSH 或加 scope |
| 远端 main 是保护分支 | 无权限 force | 在 GitHub Settings → Branches 调整，或换分支 |
| clone 下来缺少大文件 | Git LFS 未拉取 | `git lfs install && git lfs pull` |

---

## 6. 本案例（PCL-RP）实际发生过的

1. 网页/第三方 Agent 上传后，远端只有 8 个顶层文件，`src/`、`docs/`、`scripts/`、`.github/` 全部缺失；
2. 通过 `git ls-tree` + tree 对比确认是子集；
3. 把旧 HEAD 保留为 `backup/web-upload`，`--force-with-lease` 推完整 10 个提交；
4. 推 6 个 tag；
5. 独立 SSH clone 验证 27 个文件、6 个 tag；
6. 仓库随后被用户改名为 `PCL-RP`，更新 remote 与文档链接；
7. 备份分支保留，待用户确认后删除。
