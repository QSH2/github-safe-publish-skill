# 07 · 案例复盘：PCL-RP 的 GitHub 发布事故与修复

> 真实案例，2026-10。所有账号/仓库均为用户本人所有；本文只做技术复盘。
> 相关仓库（已发布）：`QSH2/PCL-RP`；旧账号 `QSH36` 已被 suspended。

---

## 1. 背景

- 项目：PCL 下载限制补丁工具（CLI + WinForms GUI），本地仓库约 27 个文件、10 个提交、6 个 tag；
- 本地有 6 个版本的发布资产（GUI exe、源码 zip、SHA256SUMS）；
- 目标：发布到 GitHub，包含源码、历史、tags、Releases。

---

## 2. 事故第一阶段：旧账号被暂停

| 时间（UTC+8） | 动作 |
| --- | --- |
| 00:09 | 使用 Windows 凭据管理器里保存的 GitHub OAuth token，通过 API 创建仓库并推送 |
| 00:10 | 通过 API 创建多个 Release 并上传资产（自动化脚本，短时间连续操作） |
| 00:10–00:30 | 账号仍可正常访问 |
| 00:30 | 带 token 请求 `GET /user` 返回 **403 `Sorry. Your account was suspended`**；主页与仓库变 404 |

### 判定

- 不是网络问题（公开页面可访问）、不是密码问题（API 明确说 suspended）；
- 账号级暂停，内容被隐藏但未删除；
- 具体原因只有 GitHub 邮件知道；**行为模式（新账号 + 短时间批量 API 写）高度可疑**。

### 处理

- 检查邮箱（无明确通知）；
- 写 Appeal/Reinstatement 信，附时间线，说明「批量自动化操作疑似触发风控、无恶意」；
- 用户重新注册新账号 `QSH2`；
- 本地内容完整，未丢失。

---

## 3. 事故第二阶段：GPT 网页上传「假成功」

用户把上传任务交给 GPT（网页/工具型）。结果：

- 远端只有一个提交：`Add files via upload`；
- 只有 8 个顶层文件：`.gitattributes`、`.gitignore`、`DISCLAIMER.md`、`LICENSE`、`NOTICE.md`、`PclCeRegionPatch.slnx`、`README.en.md`、`README.md`；
- `src/`、`docs/`、`scripts/`、`.github/` 全部缺失；
- 没有任何 tag。

### 判定方法（关键）

```powershell
git ls-tree -r --name-only origin/main      # 只有 8 个文件
git rev-parse main^{tree} vs origin/main^{tree}   # 不同
git diff --stat main origin/main            # 全是删除
```

→ 远端是本地内容的**子集**，属于「上传工具没有递归目录/只传了顶层文件」，不是内容冲突。

---

## 4. 修复：SSH 补全 + 改名同步

1. **本地准备**：
   - 更新 README/GUI 中的作者链接为 `QSH2`；
   - 生成 v1.2.4（署名更新），重打 GUI 与截图；
   - 用 `commit-tree` 把全部提交作者改写为 `清水 <347474983+QSH2@users.noreply.github.com>`，重建 6 个 tag；
   - 备份 bundle。
2. **仓库改名**：用户把仓库从 `PCL-CE-RegionPatch` 改为 `PCL-RP`；
   - 更新 remote：`git remote set-url origin git@github.com:QSH2/PCL-RP.git`；
3. **覆盖残缺远端**：
   - 旧 `fa9f97a` 保留为 `backup/web-upload` 分支；
   - `git push --force-with-lease origin main`；
   - `git push origin --tags`；
   - 独立 SSH clone 验证：27 文件、10 提交、6 tag。

---

## 5. 事故第三阶段：Release 资产「只上传了校验和」

### 5.1 第一次尝试

- 为了不暴露 token，采用临时分支 + Actions：
  - 分支 `ci/release-assets` 放 `release-assets/<tag>/` 与 `release-notes/<tag>.md`；
  - 工作流用 `GITHUB_TOKEN` + `gh release create`。
- 结果：6 个 Release 创建成功，但**每个只有 `SHA256SUMS-<tag>.txt`**。

### 5.2 根因

`.gitignore` 里有：

```text
*.exe
*.zip
```

`git add release-assets` 时 exe/zip 被静默忽略 → 提交进分支的只有 `.txt` 校验和文件。
工作流的 `gh release create ... release-assets/<tag>/*` 自然只上传了 `.txt`。

**修复**：`git add -f release-assets` 强制加入二进制，再提交/推送。

### 5.3 第二次尝试与并发/缓存问题

- 推送修正后的提交，第二个 run 显示 `success`，但直接下载资产 URL 仍 404；
- Release 页面/`expanded_assets` 有缓存，无法作为「是否存在」的证据；
- 改用**下载 URL HEAD** 判定：`302` 才是存在，`404` 即缺失。

### 5.4 调试工作流的坑

为了看日志，增加了「把日志 commit 回分支」的步骤，但第一次提交信息写成了：

```text
ci: debug asset upload and commit logs [skip ci]
```

`[skip ci]` 让 GitHub **直接跳过工作流**——等了很久没有 run。去掉 `[skip ci]` 后重新触发，
日志成功回写；`gh release upload ... --clobber` 逐个版本上传成功，全部资产变为 302。

### 5.5 其他坑

- `actions/checkout` 是 detached HEAD，回写必须 `git push origin HEAD:refs/heads/ci/release-assets`；
- 并发两次 push 可能导致两个 run 竞争（一个创建、一个上传），用幂等的 `gh release view` 保护；
- 最终清理：删除 `ci/release-assets` 分支，Release 资产保留。

---

## 6. 最终结果

| 项 | 状态 |
| --- | --- |
| 仓库 | `QSH2/PCL-RP`，public |
| 提交 | 10 个，作者 QSH2 |
| 文件 | 27 个 |
| Tags | v1.1.0 ~ v1.2.4（6 个） |
| Releases | 6 个，资产齐全 |
| Latest | v1.2.4 |
| 校验 | 所有资产 HEAD 302；下载 v1.2.4 exe 的 SHA256 与本地一致 |
| 临时分支 | 已删除；旧网页上传保留为 `backup/web-upload` |

> 补充（2026-11）：用户随后又把仓库从 `PCL-RP` 改名为 **`PCL2-RP`**。
> 旧名字的 Release 下载 URL 全部返回 **301** 到新名字；验证脚本最初把 301 当失败，
> 修正为「跟随重定向后最终 200 才算存在」后全部通过，并自动打印了改名提示。
> 这再次说明：**验证要看最终状态，不要被中间重定向误导**；仓库改名后记得同步 remote 与文档。

---

## 7. 教训清单

| # | 教训 | 对应修复/文档 |
| --- | --- | --- |
| 1 | 新账号 + 20 分钟批量 API = 高封号风险 | 06 |
| 2 | 不要复用来源不明的历史 OAuth token | 06、08 |
| 3 | SSH 不能创建 Release；别在这个方向浪费时间 | SKILL.md 能力边界、04 |
| 4 | 网页/第三方 Agent 的「上传成功」必须用 tree/文件数验证 | 03、05 |
| 5 | `.gitignore` 会吞 `*.exe`/`*.zip`，必须 `git add -f` | 04 |
| 6 | `[skip ci]` 会跳过工作流，触发提交千万别带 | 04 |
| 7 | checkout 是 detached HEAD，回写用 `HEAD:refs/heads/<branch>` | 04 |
| 8 | Release 页面/expanded_assets 有缓存，用下载 URL HEAD 302 判定 | 05 |
| 9 | 大量自动操作前先备份 bundle；force 前保留旧 HEAD 分支 | 02、03 |
| 10 | 用 GitHub 自己的 `GITHUB_TOKEN`（Actions）代替用户 token | 04 |
| 11 | 分步：main → tags → 每 Release 间隔 20–30 秒 | 02、04 |
| 12 | 发布后写机器可验证的验收记录 | 05 |

---

## 8. 可复用的产物

本 skill 把这次事故沉淀为：

- SSH 配置脚本/流程（01）；
- 安全 push 与作者改写（02）；
- 残缺仓库修复/改名（03）；
- Actions 发 Release（04）；
- 验证（05）；
- 防风控与申诉（06）；
- 可执行脚本与模板（`scripts/`、`assets/`）。

下次遇到同类任务，直接按 `SKILL.md` 的决策树走，不要重新发明。
