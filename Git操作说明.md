# Git 操作说明

> 记录本项目日常使用的 Git 操作流程，方便后续查阅。

---

## 一、如何切换分支并把内容推到 main

整体流程分三步：**提交改动 → 切换到 main → 合并并推送**。

### 1. 先看当前状态（了解情况）

```powershell
git status --short --branch   # 看当前在哪个分支、有哪些改动
git remote -v                 # 看远端仓库地址
```

例如当时结果：当前在 `develope` 分支，有 2 个文件改动（`pluto_cal.mat` 和 `run_rx_hardware.m`）。

### 2. 在当前分支提交改动

改动必须先提交（commit），否则切换分支时容易丢失或混乱。

```powershell
git add -- pluto_cal.mat scripts/hardware/run_rx_hardware.m   # 暂存改动
git commit -m "调整接收增益并更新校准数据"                        # 提交
```

- `git add`：把文件加入暂存区。
- `git commit`：把暂存内容变成一条提交记录。

### 3. 切到 main，合并 develope，再推送

```powershell
git switch main                  # 从 develope 切到 main 分支
git pull --ff-only origin main   # 先拉取远端 main，防止本地落后
git merge --ff-only develope     # 把 develope 的内容合并到 main
git push origin main             # 推送到 GitHub
```

各命令作用：

| 命令 | 作用 |
|------|------|
| `git switch main` | 切换当前分支到 `main` |
| `git pull` | 先同步远端最新内容 |
| `git merge develope` | 把 `develope` 分支的提交并入 `main` |
| `git push` | 把本地 `main` 推到远端 |

**`--ff-only` 是什么意思？**

`--ff-only` 表示"只允许快进合并"。当 `main` 落后于 `develope`（main 没有自己的新提交）时，合并会直接把 `main` 的指针"快进"到 `develope` 的位置，不产生额外的合并提交，历史更干净。

### 完整流程回顾

```powershell
# ① 在 develope 提交改动
git add -A
git commit -m "你的提交说明"

# ② 切到 main
git switch main
git pull --ff-only origin main

# ③ 合并 develope 并推送
git merge --ff-only develope
git push origin main
```

### 补充提示

- `git switch` 是 Git 2.23+ 的推荐切分支写法，比 `git checkout` 更专一、不易误操作。
- 如果 `main` 和 `develope` 各自都有新提交（不是快进关系），就不能用 `--ff-only`，要用普通 `git merge develope`，会生成一次合并提交；有冲突时需要手动解决。
- 想回到 `develope` 继续干活：`git switch develope`。

---

## 二、GitHub 重命名仓库后，远端地址不会自动改

在 GitHub 网页上 rename 仓库（例如 `matlab` → `PLUTO_project`），只改了网页端的仓库 URL，**本地 Git 的 remote 配置不会自动跟着改**。

旧地址通常还能重定向工作一段时间，所以 `git push` 仍能成功，但会提示：

```
remote: This repository moved. Please use the new location:
remote:   https://github.com/laozhan91/PLUTO_project.git
```

需要手动更新本地远端地址：

```powershell
git remote set-url origin https://github.com/laozhan91/PLUTO_project.git
```

更新后确认：

```powershell
git remote -v
# origin  https://github.com/laozhan91/PLUTO_project.git (fetch)
# origin  https://github.com/laozhan91/PLUTO_project.git (push)
```

验证新地址可正常访问：

```powershell
git ls-remote --heads origin
```

之后直接 `git push` / `git pull` 就会走新地址，无需再管。
