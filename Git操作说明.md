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

---

## 三、从 main 切到 develope

```powershell
git switch develope
```

- 因为远端已有 `develope` 分支，直接 `git switch develope` 就会切过去。
- 切换前建议保证工作区干净（`git status` 无未提交改动），否则改动会被带过去或报错。
- 切完用 `git status --short --branch` 确认显示 `## develope...origin/develope`。

### 本地没有该分支时（新克隆的机器）

Git 2.23+ 会自动找到 `origin/develope` 并创建本地跟踪分支：

```powershell
git switch develope
```

更保险的写法：

```powershell
git switch -c develope origin/develope
```

`-c` 表示创建新分支，`origin/develope` 指定跟踪远端分支。

### 其他常用切换

| 命令 | 作用 |
|------|------|
| `git switch main` | 切回 main |
| `git branch --show-current` | 查看当前分支 |
| `git branch -a` | 查看全部分支 |

---

## 四、在 develope 分支 `git pull` 拉的是谁？

**`git pull` 默认拉取当前分支跟踪的上游分支（upstream/tracking branch），不是 `main`。**

- 在 `develope` 分支 `git pull` → 拉 `origin/develope`。
- 在 `main` 分支 `git pull` → 拉 `origin/main`。

`git pull` = `git fetch` + `git merge`（合并到当前分支），合并对象是当前分支配置的上游分支。

### 查看当前分支跟踪哪个上游

```powershell
git status --short --branch
# 显示 ## develope...origin/develope，`...` 后面的就是 pull 目标
```

或者：

```powershell
git branch -vv
# develope 96f73a0 [origin/develope] ...
# main     b735bfd [origin/main] ...
```

`[origin/xxx]` 里的就是该分支跟踪的远端。

### 如何把 main 的改动同步到 develope

不能靠裸 `git pull`，要主动合并 `main`：

```powershell
# 确保在 develope 分支
git switch develope

# 先拉取远端 main
git fetch origin

# 把 origin/main 合并进当前 develope 分支
git merge origin/main
```

或更简洁的两步：

```powershell
git pull origin main
```

注意：`git pull origin main` 是**临时**拉取 `origin/main` 并合并到当前分支，**不会**改变 develope 的默认上游配置——以后裸 `git pull` 仍然拉 `origin/develope`。

### 小结

| 操作 | 拉取/合并的内容 |
|------|----------------|
| `git pull`（在 develope） | `origin/develope` |
| `git pull`（在 main） | `origin/main` |
| `git pull origin main`（在 develope） | 把 `origin/main` 合并进当前分支 |

**想拉 main 的改动，用 `git pull origin main`（或 `git merge origin/main`）；只想同步 develope 自己，裸 `git pull` 就够了。**
