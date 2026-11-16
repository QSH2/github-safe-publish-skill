# GitHub Safe Publish Skill

> 给 AI Agent 用的 **GitHub 安全发布技能包**：SSH 推送、不暴露 token 地发 Release、残缺仓库修复、发布后逐项校验，以及新账号防风控/申诉。
>
> 来源是一次真实的「GitHub 上传事故」复盘：新账号在 20 分钟内用 API 批量建仓 + 发 Release 被 **suspended**，改用 **SSH + GitHub Actions** 后完成了零 token、可验证的完整发布。
>
> 多文件、渐进式披露：`SKILL.md` 只是目录与决策树，细节按需加载，节省 Agent 上下文。

---

## 这是什么

一个符合 **SKILL.md 技能格式** 的多文件技能目录，包含 15 个文件：

```text
github-safe-publish-skill/
├─ SKILL.md                              # 技能入口：能力边界 / 决策树 / 30 秒速查 / 验收清单
├─ references/
│  ├─ 01-ssh-windows-setup.md            # Windows 无管理员装 OpenSSH、keygen、指纹校验
│  ├─ 02-git-push-safety.md              # bundle 备份、先 main 后 tags、force-with-lease、作者改写
│  ├─ 03-repo-repair-and-rename.md       # 网页残缺上传识别、tree 对比、仓库改名同步
│  ├─ 04-release-without-token.md        # 用临时 Actions + GITHUB_TOKEN 发 Release（核心）
│  ├─ 05-verification.md                 # clone / tree / HEAD 重定向 / SHA256 / latest 验证
│  ├─ 06-anti-suspension.md              # 风控预防、suspended 症状、申诉模板
│  ├─ 07-case-study-pcl-rp.md            # 真实事故完整时间线
│  └─ 08-token-and-device-flow.md        # PAT / OAuth device flow / 网页手动对比
├─ scripts/
│  ├─ check-ssh-github.ps1               # 只读：SSH、refs、tree、文件数、tags
│  ├─ verify-release-assets.ps1          # Release 资产 HEAD 校验 + latest + SHA256
│  ├─ make-release-workflow.ps1          # 由 JSON 清单生成发版工作流
│  └─ push-main-then-tags.ps1            # 安全推送（main → 等待 → tags），带 dry-run
├─ assets/
│  ├─ create-releases.yml.template       # Actions 发版工作流模板
│  └─ release-manifest.example.json      # 发版清单示例
├─ README.md
├─ LICENSE
├─ .gitignore
└─ install.ps1                           # 一键安装到 DSH skills 目录
```

---

## 为什么需要它

真实事故摘要：

1. 新注册的 GitHub 账号在约 20 分钟内用脚本创建仓库、发多个 Release、上传多份资产；
2. 账号被 GitHub 风控 **suspended**（`GET /user` 返回 `403 Sorry. Your account was suspended`），仓库/主页都变 404；
3. 更换新账号后，先被第三方 Agent「网页上传成功」误导（实际只上传了 8 个顶层文件，`src/`、`docs/` 全缺）；
4. 用 SSH 覆盖修复完整历史，再临时推一个 Actions 工作流，用仓库自带的 `GITHUB_TOKEN` 创建 6 个 Release；
5. 期间踩了 `.gitignore` 吞 `*.exe`、`[skip ci]` 跳过工作流、detached HEAD 回写、301 改名重定向等坑；
6. 最终全部资产通过独立下载校验（最终 200 + SHA256 一致）。

这个技能把上述流程、命令和坑全部固化成可复用文档与脚本。

---

## 快速开始

### 方式 A：一键安装（DSH）

```powershell
git clone https://github.com/QSH2/github-safe-publish-skill.git
cd github-safe-publish-skill
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

默认安装到 `%USERPROFILE%\.dsh\skills\github-safe-publish`；也可指定：

```powershell
.\install.ps1 -TargetRoot "D:\agents\skills" -Force
```

### 方式 B：手动复制

把整个目录复制到你的 Agent 的 skills 目录，并确保目录名与 `SKILL.md` 里的 `name` 一致：

```text
~/.dsh/skills/github-safe-publish/SKILL.md
```

重启/新建 Agent 会话后即可被技能目录发现。

### 触发方式

在支持技能自动路由的 Agent 中，命中以下关键词会自动加载：

> GitHub 上传、SSH 推送、SSH 配置、Release 发布、发版、仓库改名、网页上传缺文件、GitHub 封禁/suspended、Actions 发版、release 资产、git push 失败、github 风控

也可以手动指定：

```text
skill github-safe-publish
```

---

## 使用决策树

```text
你要做什么？
├─ 这台 Windows 还没配 GitHub SSH
│   → references/01（便携 OpenSSH + ed25519 + 公钥加到 GitHub + 验证）
├─ 有本地仓库要首次推到 GitHub
│   → references/02（bundle 备份 → push main → push tags）
├─ 远端仓库内容残缺 / 刚改名 / 历史不对
│   → references/03（先对比 tree，再决定 force；保留旧内容分支）
├─ 要把版本发布成 GitHub Release（要上传 exe/zip 资产）
│   ├─ 不想给任何 token → references/04（SSH 推临时分支 + Actions GITHUB_TOKEN）
│   ├─ 可以授权一次 → references/08（device flow / fine-grained PAT）
│   └─ 数量少（1 个）→ 网页手动也可以，但按 05 校验
├─ 发布完了要验收
│   → references/05（clone、tree、HEAD 最终 200、SHA256、latest）
├─ 账号被 suspended / 怀疑被风控
│   → references/06（先查邮箱与申诉，不要开新号绕）
└─ 想复盘真实事故
    → references/07
```

---

## 脚本用法

> 所有脚本都是 PowerShell 5.1+，Windows 10/11 自带 `curl.exe`；只读脚本不需要 token。

### 1. 检查 SSH 与仓库一致性

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-ssh-github.ps1 `
  -RepoPath "E:\your-repo" -Repo "owner/repo"
```

输出：SSH 认证结果、远端 heads/tags、本地与远端 tree 是否一致、文件数、缺失的 tag。
退出码 0 = 全部通过。

### 2. 校验 Release 资产

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-release-assets.ps1 `
  -Repo "owner/repo" -AssetDir ".\release-assets" -CheckLatest -ExpectedLatest v1.2.4
```

- 逐个资产跟随重定向后检查最终 `200`（`301` = 仓库改名，不会误判为缺失）；
- `-CheckHashes` 会下载资产并与 `SHA256SUMS-<tag>.txt` 对比；
- `-CheckLatest` 解析 `/releases/latest` 的最终 URL。

### 3. 生成临时发版工作流

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\make-release-workflow.ps1 `
  -ManifestPath .\release-manifest.json -OutFile .\.github\workflows\create-releases.yml -DebugLog -Force
```

生成后按 `references/04` 推临时分支、等 Actions 跑完、校验、删分支。

### 4. 安全推送

```powershell
# 先看会发生什么
powershell -ExecutionPolicy Bypass -File .\scripts\push-main-then-tags.ps1 -RepoPath "." -DryRun

# 正式执行（自动先推 main，再等 60 秒推 tags；可加 -BackupBundle）
powershell -ExecutionPolicy Bypass -File .\scripts\push-main-then-tags.ps1 -RepoPath "." -BackupBundle
```

---

## 核心原则

1. **SSH 只能推 git 对象**，创建/更新 Release 必须走 API、网页或 Actions，别在 SSH 上找办法。
2. **新账号不要短时间批量写 API**：main → tags → 每个 Release 间隔 20–30 秒以上。
3. **不信任「上传成功」**：用 tree 哈希、文件数、独立 clone、资产 HEAD 200、SHA256 验收。
4. **发版资产常被 `.gitignore` 吞掉**（`*.exe`/`*.zip`）：提交临时分支时 `git add -f`。
5. **`[skip ci]` 会跳过工作流**：需要触发的提交不要带；只有工作流回写日志的自动提交才加。
6. **Actions checkout 是 detached HEAD**：回写分支用 `git push origin HEAD:refs/heads/<branch>`。
7. **资产校验要跟随重定向**：最终 200 才存在；301 通常只是仓库改名。
8. **force 前必须备份**：`git bundle create --all` + 旧 HEAD 保留为 `backup/...` + `--force-with-lease`。
9. **作者改写用 `commit-tree` + `-F`**（UTF-8 无 BOM），不要用 PowerShell 管道传中文提交消息。
10. **私钥永不外发**；token 不打印、不进仓库、用完撤销。

---

## 能力边界

| 目标 | SSH | 需要 |
| --- | --- | --- |
| 推送提交/分支/tag | ✅ | — |
| 创建/更新 Release | ❌ | 网页 / REST API / GitHub Actions |
| 上传 Release 资产 | ❌ | 同上 |
| 修改 Topics/描述 | ❌ | 网页或 API |
| 验证仓库完整性 | ✅ | git clone / ls-remote / tree |
| 验证 Release 资产 | — | HTTP HEAD（跟随重定向）或下载校验 |

---

## 安全说明

- 本仓库**不包含**任何 token、密钥、密码、个人访问凭据；
- 脚本默认只读；`push-main-then-tags.ps1` 只执行普通 `git push`（不含 force）；
- 发 Release 的方案不接触用户密码，使用 GitHub Actions 仓库级 `GITHUB_TOKEN`；
- 如按 references/08 使用 PAT/device flow，请使用最小权限并在完成后撤销。

---

## 兼容性

- 文档：跨平台（命令以 PowerShell / bash 为主）；
- 脚本：Windows 10/11 + PowerShell 5.1+（使用 `curl.exe`；Windows 10 1809+ 自带）；
- 技能格式：`SKILL.md` + YAML frontmatter（name / description / author），references 使用相对路径；
- 不绑定特定 Agent：任何支持「按 SKILL.md 加载 + 相对资源」的 Agent 都可使用。

---

## 贡献 / 反馈

- 发现新坑：在 Issue 里给出「现象 / 复现命令 / 修复」三件套；
- 修改脚本：保持只读默认、显式 `-DryRun`/`-Force` 风格，并附一次真实运行输出；
- 不要提交任何真实 token、私钥或未脱敏日志。

---

## License

[MIT](LICENSE) © 2026 QSH2（清水Shimizu）

---

## English summary

A multi-file skill for AI agents that covers **safe GitHub publishing**:

- Windows OpenSSH setup without admin rights, SSH key onboarding, host fingerprint checks;
- safe `git push` (main then tags, bundle backup, `--force-with-lease`, author rewrite);
- repairing partially-uploaded repos and handling repository renames;
- **creating GitHub Releases without exposing a user token** via a temporary Actions
  workflow using the repo-scoped `GITHUB_TOKEN`;
- end-to-end verification (independent clone, tree comparison, asset HEAD follow-redirect,
  SHA256, latest release);
- anti-suspension practices and an appeal template, based on a real incident.

It includes 8 reference documents, 4 PowerShell scripts, 2 templates and this README.
No secrets are included.

---

## 作者

- 清水Shimizu（GitHub: [@QSH2](https://github.com/QSH2)）
- 本技能来自真实项目与事故复盘；欢迎 fork / 提 Issue / 提 PR。
