# 06 · GitHub 风控/封号：预防与申诉

> 来源：真实事故——新账号在约 20 分钟内完成「建仓 + 多个 Release + 多资产上传」后被
> GitHub **suspended**，没有事先警告。本文件总结症状、原因、预防与申诉流程。

---

## 1. 症状（如何确认是 suspended，而不是网络/密码问题）

| 检查 | 表现 |
| --- | --- |
| `GET https://api.github.com/user`（带 token） | `HTTP 403`，body：`{"message":"Sorry. Your account was suspended","documentation_url":"https://docs.github.com/rest","status":"403"}` |
| 个人主页 `https://github.com/<user>` | `HTTP 404`（页面显示 Not Found） |
| 仓库页 `https://github.com/<user>/<repo>` | `HTTP 404` |
| 登录页 | 可能提示 suspended / 无法登录 |
| 公开 API `/users/<user>` | 可能 403（限流）或 404 |

注意区分：

- **404 但能登录** → 仓库改名/转私有/删除；
- **403 "suspended"** → 账号级暂停；
- **403 rate limit** → IP 限流，换时间/换网络，不是封号。

---

## 2. 账号暂停意味着什么

- 不是立即删除：账号内容（仓库、Issue、Release）通常**被隐藏但保留**；
- 申诉成功后可恢复；
- 申诉/恢复窗口：GitHub 政策说明为**决定后 6 个月内**可申请（Reinstatement/Appeal），
  超过可拒绝受理；
- 被暂停期间：
  - 无法登录网页、无法使用 API token（token 也会被拒）；
  - 无法 clone 私有仓库；
  - 已推送的公开内容对外不可见。

---

## 3. 常见触发/加速因素

GitHub 不会公开具体原因（只发到账号邮箱），但以下行为会显著增加被自动风控的概率：

1. **新注册账号 + 短时间大量写操作**：建仓、批量 Release、批量上传资产、批量 star/fork；
2. **用脚本/第三方工具高频调用 API**，且来自异常 IP/代理；
3. **复用一个来源不明的 OAuth token**（例如从其他软件凭据管理器里读出来的）；
4. **多账号同一设备/IP 频繁互操作**（互 star、搬运仓库）；
5. 内容被举报、疑似 spam/滥用；
6. 明显的自动化网页操作（高频点击/提交）。

> 关键教训：**GitHub 判定「自动化批量」并不区分你是正常用户还是机器人**。
> 新账号尤其敏感，任何「20 分钟内完成整套发布」都容易被盯上。

---

## 4. 预防清单

### 4.1 账号层

- 验证邮箱、开启 2FA、完善头像/简介；
- 新账号先正常使用几天（浏览、star、少量提交）再做大动作；
- 不要在同一网络/设备上批量切换多个账号。

### 4.2 操作层

- **分步、分时**：main → 等 1–2 分钟 → tags → 等 → 每个 Release 间隔 20–30 秒以上；
- 能分天完成就不要一次做完；
- 不要用脚本一次性创建多个仓库/Release/大量资产；
- 优先用 **SSH**（git 协议）推代码：这是正常开发行为，风险低；
- Release 用 GitHub Actions 的 `GITHUB_TOKEN`（见 04），而不是用户 token 批量 API；
- 避免使用「一键刷仓库/批量建仓」的第三方服务。

### 4.3 凭据层

- 不把密码/长期 token 交给任何第三方（包括 AI 工具）；
- 如必须用 PAT：fine-grained、只勾选目标仓库、最短有效期、用完立即撤销；
- 不在日志/聊天/仓库里出现 token；`gh auth status` 会显示 `ghs_***`，公开仓库日志要避免；
- 不轻易从凭据管理器读取并使用「历史遗留 token」——它们可能已经泄露/被标记。

---

## 5. 被暂停后的处理流程

### 5.1 先查邮箱

- 检查注册邮箱（含垃圾箱）是否有 GitHub Support 邮件；
- 邮件通常会说明原因/申诉方式；直接回复该邮件是最快路径之一。

### 5.2 申诉入口

- 账号暂停专用：<https://support.github.com/contact/account-suspension>
- 一般联系：<https://support.github.com/contact>
- 政策与流程（Appeal/Reinstatement）：
  <https://docs.github.com/en/site-policy/acceptable-use-policies/github-appeal-and-reinstatement>
- 无法登录时，按 GitHub 文档的 "Unable to sign in to contact GitHub Support" 流程验证邮箱后访问表单。

### 5.3 选对类型

| 类型 | 适用 |
| --- | --- |
| **Appeal（申诉）** | 认为没有违规，要求撤销决定 |
| **Reinstatement（申请恢复）** | 承认可能违反政策，愿意整改并承诺遵守 |

### 5.4 申诉信模板（简短、带时间线）

```text
Subject: Appeal request for suspended account <username>

Hello GitHub Support,

My account "<username>" was suspended on <date> (UTC+8) without any
prior notice or warning. I was completely unaware of any violation.

Timeline (UTC+8):
- 00:09  I used <tool> on my own PC to create my repository <repo>
        and push its source code.
- 00:10  I published several releases (build artifacts and source zips)
        for my own open-source project in a very short time.
- 00:30  My account was suspended, with no notification or explanation.

The suspension appears to have been triggered by that short burst of
automated batch operations. All actions were performed by me, or by the
assistant under my direct instruction, on my own account. There was no
spam, no fake engagement and no bulk account creation.

I had no idea anything was wrong and received no warning. I am happy to
provide any verification or adjust my usage pattern. Please review my
case and reinstate my account.

Thank you,
<username>
```

补充：

- 如果收到邮件写明原因，逐条回应，不要套模板；
- 不要提交虚假信息；
- 一次一个工单，不要刷屏；
- 等待期间不要开新账号搬运内容（可能被认定为规避封禁）。

### 5.5 数据与备份

- 本地仓库、bundle、发布包、Release 资产都在本地的话，账号恢复后可重新推送；
- 如果旧账号无法恢复：**先处理申诉**，不要用新账号直接搬运被暂停账号的内容；
- 迁移到其他平台（GitLab/Gitee）可以作为备份方案，但不要用于规避平台处罚。

---

## 6. 本次事故时间线（真实）

| 时间（UTC+8） | 事件 |
| --- | --- |
| 00:09 | 用保存的 OAuth token 创建仓库并推送 |
| 00:10 | 创建多个 Release 并上传资产 |
| 00:10–00:30 | 账号仍可访问 |
| 00:30 | 发现 `GET /user` 返回 403 `Sorry. Your account was suspended`；主页/仓库 404 |
| 后续 | 写申诉信；注册新账号；改用 SSH + Actions 方案重新发布 |

结论：**不是内容问题，是行为模式问题**。减小「短时间 + 批量 + 自动化」特征是最有效的预防。

---

## 7. 事后复盘清单

- [ ] 账号已恢复 / 已放弃（不要双开）
- [ ] 2FA/邮箱已确认
- [ ] 旧 token 已撤销（如还能登录）
- [ ] 本地仓库有完整备份（bundle + 发布资产）
- [ ] 新发布流程已改为分步 + SSH/Actions
- [ ] 后续同类操作有节奏限制（每次间隔、每日上限）
- [ ] 记录本次错误，写进团队/个人 Runbook（即本 skill）
