# 01 · Windows 无管理员安装 OpenSSH 并接入 GitHub

> 目标：在这台 Windows 上得到可用的 `ssh` / `ssh-keygen`，把公钥加到 GitHub，`ssh -T git@github.com` 成功。
> 适用：Windows 10/11，当前用户**没有管理员权限**（无法安装「可选功能」OpenSSH）。

---

## 1. 先判断现状

```powershell
where.exe ssh 2>$null
ssh -V
Get-WindowsCapability -Online -Name "OpenSSH*"   # 非管理员会报 "requires elevation"
$env:USERPROFILE\.ssh                            # 是否已有 known_hosts/key
```

常见结果与对策：

| 现状 | 对策 |
| --- | --- |
| `ssh` 不存在，能力安装提示需要 elevation | 用下面的**便携版 Win32-OpenSSH** |
| 只有 MinGit / Git for Windows 的 `ssh` | 可能**缺少 `ssh-keygen.exe`**（实测 MinGit 只有 ssh/ssh-add/ssh-agent）→ 仍建议装便携版 |
| 已有 Windows OpenSSH | 直接跳到第 3 节生成密钥 |

> 便携版是微软官方 `PowerShell/Win32-OpenSSH` 的发布包，功能与系统 OpenSSH 相同，只是不注册系统服务、不写系统目录。

---

## 2. 安装便携版（无需管理员）

```powershell
# 2.1 找最新发布（latest 可能是 Preview；下方 fallback 是稳定 Beta）
$loc = (curl.exe -sIL -H "User-Agent: Mozilla/5.0" "https://github.com/PowerShell/Win32-OpenSSH/releases/latest" |
  Select-String -Pattern '^location:' | Select-Object -Last 1).ToString()
Write-Host $loc

# 2.2 下载 Win64 zip（示例：稳定版 v9.5.0.0p1-Beta；也可换成 latest 中的 tag）
$url = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip"
$zip = "$env:TEMP\OpenSSH-Win64.zip"
curl.exe -sL --retry 3 --max-time 300 -o $zip $url
if ((Get-Item $zip).Length -lt 1MB) { throw "下载不完整" }

# 2.3 解压到用户目录
$dest = "$env:LOCALAPPDATA\Programs\OpenSSH"
Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
$tmp = "$env:TEMP\OpenSSH-extract"
Expand-Archive $zip $tmp -Force
Copy-Item "$tmp\OpenSSH-Win64\*" $dest -Recurse -Force
Remove-Item $tmp -Recurse -Force

# 2.4 加入【用户级 PATH】
$userPath = [Environment]::GetEnvironmentVariable('Path','User')
if ($userPath -notlike "*$dest*") {
  [Environment]::SetEnvironmentVariable('Path', "$dest;$userPath", 'User')
}
```

验证（**用绝对路径**，因为当前进程不会刷新 PATH）：

```powershell
& "$env:LOCALAPPDATA\Programs\OpenSSH\ssh.exe" -V   # 版本输出到 stderr，属正常
```

> 重要：用户级 PATH 只对**新启动**的进程生效。已经打开的终端/IDE/Agent 进程仍看不到；
> 在当前进程里可临时 `$env:Path = "$dest;$env:Path"`，或写脚本时使用绝对路径。

---

## 3. 生成 ed25519 密钥（无口令）

PowerShell 5.1 调用原生程序时会**丢弃空字符串参数**，直接 `-N ""` 会导致 ssh-keygen 进入交互。
用 `.bat` + `cmd /c` 传空引号最稳：

```powershell
$openssh = "$env:LOCALAPPDATA\Programs\OpenSSH"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null

$bat = "$env:TEMP\gen-ssh-key.bat"
@"
@echo off
"$openssh\ssh-keygen.exe" -q -t ed25519 -C "you@example.com" -f "%USERPROFILE%\.ssh\id_ed25519" -N ""
"@ | Set-Content $bat -Encoding ASCII
cmd.exe /c $bat
Remove-Item $bat -Force
```

验证「确实没有口令」：

```powershell
cmd.exe /c "`"$openssh\ssh-keygen.exe`" -y -f `"$env:USERPROFILE\.ssh\id_ed25519`" < NUL"
```

- 输出以 `ssh-ed25519 ...` 开头 → 无口令；
- 若要求输入口令 → 生成失败，删掉 `.ssh\id_ed25519*` 重来。

> 需要口令时：`ssh-keygen -p -f %USERPROFILE%\.ssh\id_ed25519` 加口令；无管理员时
> Windows `ssh-agent` 服务装不了，可手动运行便携版 `ssh-agent.exe` + `ssh-add.exe`，
> 或每次连接手动输入。自动化场景建议先用无口令 key，并保证私钥文件权限。

---

## 4. known_hosts：必须校验 GitHub 主机指纹

```powershell
# 方式 A：若 ssh-keyscan 可用（代理环境可能失败）
& "$openssh\ssh-keyscan.exe" -T 15 -t ed25519 github.com |
  Set-Content "$env:USERPROFILE\.ssh\known_hosts" -Encoding ASCII

# 方式 B：已有 known_hosts 时直接算指纹
& "$openssh\ssh-keygen.exe" -lf "$env:USERPROFILE\.ssh\known_hosts" -E sha256
```

GitHub 官方 ED25519 指纹（可在 GitHub Docs「GitHub's SSH key fingerprints」核对）：

```text
SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU
```

- 指纹匹配 → 可以继续；
- 不匹配 / `ssh-keyscan` 无输出 → 不要 `StrictHostKeyChecking=no` 盲连；换网络或从官方文档抄指纹
  手动写 `known_hosts`。

---

## 5. 写 `~/.ssh/config`

```text
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host ssh.github.com
    HostName ssh.github.com
    User git
    Port 443
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

- 默认 22；若公司/运营商封 22，用 `ssh -T -p 443 git@ssh.github.com` 或把 Host 换成 443 配置。
- 多账号：给不同 Host 别名（`github-work`）配不同 IdentityFile。

写文件时用 UTF-8 **无 BOM**（PowerShell 5.1 的 `Set-Content -Encoding UTF8` 会带 BOM；
config 带 BOM 通常也能读，但用 `WriteAllText + UTF8Encoding($false)` 更干净）。

---

## 6. 让 Git 使用这个 OpenSSH

```powershell
git config --global core.sshCommand "C:/Users/<you>/AppData/Local/Programs/OpenSSH/ssh.exe"
```

- **必须用正斜杠**。`GIT_SSH_COMMAND` 里的 Windows 反斜杠会被 Git 的 shell 解析吃掉，
  出现 `C:Userstimpr...: command not found` 这类怪错。
- 设置后 `git ls-remote git@github.com:<owner>/<repo>.git` 应能直接工作。

---

## 7. 把公钥加到 GitHub

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard
Start-Process "https://github.com/settings/ssh/new"
```

浏览器（已登录目标账号）操作：

1. **Title**：`Windows-OpenSSH`（或设备名）
2. **Key type**：`Authentication Key`
3. **Key**：`Ctrl+V` 粘贴（只粘贴 `.pub` 内容）
4. **Add SSH key**；如要求密码/2FA 按提示完成

验证：

```powershell
& "$env:LOCALAPPDATA\Programs\OpenSSH\ssh.exe" -o BatchMode=yes -T git@github.com
```

成功输出（**退出码仍为 1**，这是正常的，要解析文字而不是 exit code）：

```text
Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.
```

失败输出：

```text
git@github.com: Permission denied (publickey).
```

→ 公钥没加、加错账号、key 路径不对，或 config 的 `IdentityFile` 写错。

---

## 8. 安全与运维

- **私钥永不外发**：只上传 `.pub`；不要把 `id_ed25519` 发给任何 Agent/群/网盘。
- 备份：把 `.pub` 和一份加密的私钥备份到可信介质；换机时重新生成并在 GitHub 删旧 key。
- 删除 key：GitHub Settings → SSH and GPG keys → Delete；本地 `~/.ssh/id_ed25519*` 删除。
- 如果 key 泄露：立刻在 GitHub 删除该公钥，并重建 key。
- 不把 `~/.ssh` 提交进仓库；`.gitignore` 里加 `.ssh/`、`*.pem`、`id_*`（但 `id_*.pub` 也不该乱传）。
