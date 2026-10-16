# claude-restore-kit

**用了一段时间网关版的 Claude Desktop，现在想回到自己的 Anthropic 账号，但不想丢掉那段时间的会话、定时任务和记忆。**

[中文](#中文) · [English](#english)

---

## 中文

**从网关（"3p"）模式回到正常登录的 Claude 账号，一个文件都不用丢。**

你先是因为封号（或者别的什么原因）把 Claude Desktop 切到了网关模式，用 CC Switch
之类的工具让它连国产模型的 API。用了一段时间，攒下了一堆会话、定时任务、记忆。
现在你想回到自己的 Anthropic 账号了。

登录之后你会发现，左边栏是空的。之前那些东西好像都没了。

其实都在。它们在网关模式用的那个数据目录里，一个字都没少。Claude Desktop
按账号去读**另一个文件夹**而已。

这个项目是一套**技能 + 脚本**，把网关模式下的工作内容原样搬回你的账号，包括会话、
定时任务、Cowork 会话。它是 [`claude-migration-kit`](https://github.com/zhangwenhao66/claude-migration-kit)
的反向版本——那个是把东西搬**出去**，这个是搬**回来**。

> 在 macOS 上实测跑通。原理与平台无关，但路径在 Linux/Windows 上不同。

### 往回搬比往外搬多两件事

往外搬的时候，目标分区是全新的、空的。往回搬不一样，有两个坑是反向独有的。

**第一，目标分区是活的。** 你刚登录的账号可能已经有它自己的会话和定时任务了。
所以这个仓库**不覆盖**，它按 id **合并**。

这里有个**必须先知道**的点。任务 id 是人可读的 slug（`daily-backlink-building` 这种），
**不是 uuid**，所以只要两边跑的是同一批任务，**id 就会全部撞上**。这不是小概率，是常态——
写这个仓库的机器上就是 110 个撞 110 个，账号侧有 76 个正在跑。

撞上的时候只能留一个定义，取网关侧的那份，而且**导入后是停用状态**。意味着账号侧
本来在跑的同名任务**会被关掉**。这是有意的（工具绝不自己启动任何任务），但它确实
会停掉你原本在跑的东西，所以脚本会把名单单独存下来：

- `target-was-enabled-<时间戳>.txt`，导入前**账号侧**原本启用的全部任务
- `task-merge-report-<时间戳>.txt` 里「WAS running in the account, now DISABLED」那一段，本次真正被关掉的

要不要恢复、恢复哪几条由你决定，**但先核模型 id**，因为那条任务的定义现在来自网关侧。
只有网关侧没有、账号侧独有的 id 才是完全不动，连启用状态都不碰。

**第二，机器上还留着网关的痕迹。** 退出登录**不会**清掉 shell 里的
`ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN`。每开一个新终端、每跑一个定时任务，
都会继续走网关——而且**不报任何错**。本仓库带一个 `check-gateway.sh` 专门查这个，
必须在启用任何任务之前跑。

### 项目内容

| 文件 | 说明 |
|---|---|
| `SKILL.md` | Claude Code 技能。装好后直接对 Claude 说"把网关模式的 Claude 迁回我的账号"，它带你走完全程。 |
| `scripts/find-partitions.sh` | 只读：找出所有分区，并打印**哪些任务是启用的**（这份清单要存好）。 |
| `scripts/restore.sh` | `check` / `test` / `all`：备份 → 合并会话 → **按 id 合并任务（停用状态导入）** → 搬 Cowork。全程只复制。 |
| `scripts/check-gateway.sh` | 只读：查机器上是否还残留网关配置（环境变量、切换器、浏览器 MCP）。**启用任务前必须跑。** |
| `scripts/restore-enabled.sh` | 按原样恢复启用状态，**支持分批**，带 `--dry-run`。 |
| `scripts/rollback.sh` | 清单式精确回滚，只删它自己复制过的文件。 |
| `docs/01-data-layout.md` | 数据怎么存的、为什么看起来全没了、两个方向的对照表。 |
| `docs/02-restore.md` | 逐步恢复与验收，含 `TASK_MODE` 三种语义。 |
| `docs/03-leaving-gateway.md` | **反向独有**：怎么真正离开网关模式，残留怎么清。 |
| `docs/04-browser.md` | 回到账号后浏览器怎么办——换回官方扩展，还是留着开源桥。 |
| `docs/05-pitfalls.md` | 我们踩过的坑，反向独有的排在最前面。 |
| `docs/06-verification.md` | 验收清单：怎么确认真的搬回来了。 |

安装技能：

```bash
mkdir -p ~/.claude/skills/claude-account-restore
cp SKILL.md ~/.claude/skills/claude-account-restore/SKILL.md
```

（仓库留着别删——技能里会让 Claude 从这个仓库跑脚本。）

### 快速开始

```bash
git clone https://github.com/zhangwenhao66/claude-restore-kit.git && cd claude-restore-kit

bash scripts/find-partitions.sh        # 1. 找源（Claude-3p）和目标（Claude）；抄下 Claude-3p 那一段的启用清单
cp scripts/config.example.sh scripts/config.sh && $EDITOR scripts/config.sh   # 2. 填配置
bash scripts/restore.sh check          # 3. 只读预检（Claude 开着也能跑）

# 4. 先离开网关模式（见 docs/03），然后确认没有残留：
bash scripts/check-gateway.sh          # 必须看到 app 用的是 .../Application Support/Claude

# 5. 完全退出 Claude Desktop（⌘Q），然后：
bash scripts/restore.sh test           # 只搬 20 条，重开 Claude 肉眼确认
bash scripts/restore.sh all            # 全量；任务按 id 合并，且全部停用

# 6. 读一遍 task-merge-report-*.txt，再分批恢复启用：
bash scripts/restore-enabled.sh --dry-run
bash scripts/restore-enabled.sh --limit 5
```

> 第 4 步不能跳过。App 还在网关模式时，你写进去的是它**没在读**的那个分区，
> 看起来就像迁移失败了。

### 什么能搬回来

| 资产 | 搬得回来？ | 说明 |
|---|---|---|
| 对话正文 | ✅ | 本来就共享，App 只差元数据 |
| 会话列表（标题、文件夹分组） | ✅ | 同名时按 `lastActivityAt` 取更新的那份，被覆盖的旧版存进 `replaced-sessions/` |
| 定时任务 / Routine | ✅ | **按 id 合并**，停用状态导入；之后分批恢复 |
| 技能、记忆、`CLAUDE.md` | ✅ | 不按账号隔离，什么都不用做 |
| 项目文件与 git | ✅ | 从头到尾没碰 |
| Cowork 会话 | ✅ | 独立分区，同样的方法（注意目录名是截断的） |
| Cowork 工作区 / memory / 用量账本 | ❌ | 只搬 `local_*` 和 `spaces`，其余不搬，脚本会明说 |
| 浏览器自动化 | ⚠️ | 有付费套餐就能换回官方扩展；否则继续用开源桥，见 docs/04 |
| 插件 | ❌ | 按账号从市场同步，需重装 |
| 已发布的 Artifact / claude.ai 网页对话 | ❌ | 绑死在账号上，无法找回 |

### 环境要求

macOS、`bash`、`python3`、Claude Desktop。

### 先读哪两章

[`docs/03-leaving-gateway.md`](docs/03-leaving-gateway.md)（先离开网关模式）和
[`docs/05-pitfalls.md`](docs/05-pitfalls.md)（反向独有的坑都在最前面）。

### 参与贡献

如果你踩到了这个项目没提醒的坑——那是最有价值的反馈，见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可

MIT —— 见 [LICENSE](LICENSE)。

---

## English

You spent a while on Claude Desktop in gateway ("3p") mode — CC Switch or similar pointing it
at a third-party API — and now you want to go back to your own Anthropic account without losing
what you built there.

After logging in, the sidebar is empty. It isn't. Your sessions, routines and memory are in the
data directory the gateway deployment used, untouched. Claude Desktop just reads a **different
folder** per account.

This kit is a **skill + scripts** that move everything back: sessions, scheduled tasks, Cowork.
It is the reverse of [`claude-migration-kit`](https://github.com/zhangwenhao66/claude-migration-kit).

> Battle-tested on macOS. The technique is platform-independent; paths differ on Linux/Windows.

### Coming back is not just the same thing backwards

Two things differ, and both bite.

**The target is live.** The account you just signed into may already have its own sessions and
routines. So this kit **merges** rather than replaces, by task id.

**Know this before you run it.** Task ids are human-readable slugs (`daily-backlink-building`),
**not** uuids. If both deployments run the same task set, *every* id collides — that is the
normal case, not an edge case. On the machine this kit was written on, 110 of 110 collided and
the account side had 76 of them running.

When an id collides there is room for one definition, the gateway's wins, and the task is
imported **disabled**. So an account-side routine that was running stops. That is deliberate —
the kit never starts a task by itself — but it does switch off work you had going, so the script
records it:

- `target-was-enabled-<stamp>.txt` — everything that was enabled in the **account** before the
  import;
- the *"WAS running in the account, now DISABLED"* section of `task-merge-report-<stamp>.txt` —
  the ones this run actually switched off.

Restoring any of them is your call — but check the model id first, because the task definition
is now the gateway's. Only ids that exist **solely** in the account are left untouched, enabled
state and all.

**The machine still points at the gateway.** Logging out does **not** remove
`ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` from your shell profiles. Every new terminal and
every scheduled task keeps calling the gateway, and **nothing errors**. `scripts/check-gateway.sh`
exists for exactly this, and must run before you enable anything.

### What's in here

| File | What it is |
|---|---|
| `SKILL.md` | A Claude Code skill. Install it and just ask Claude *"restore my gateway-mode Claude into my account"*. |
| `scripts/find-partitions.sh` | Read-only: finds every partition, and prints **which tasks were enabled**. |
| `scripts/restore.sh` | `check` / `test` / `all` — backup → merge sessions → **merge tasks by id (imported disabled)** → Cowork. Copy-only. |
| `scripts/check-gateway.sh` | Read-only: hunts gateway residue (env vars, switchers, browser MCPs). **Run before enabling anything.** |
| `scripts/restore-enabled.sh` | Re-enable exactly the tasks that were enabled before — **in batches**, with `--dry-run`. |
| `scripts/rollback.sh` | Precise, manifest-based undo. Only deletes what it copied. |
| `docs/` | Data layout, the restore walkthrough, leaving the gateway, browser options, pitfalls, verification. |

### Quick start

```bash
git clone https://github.com/zhangwenhao66/claude-restore-kit.git && cd claude-restore-kit

bash scripts/find-partitions.sh        # 1. find source (Claude-3p) and target (Claude)
cp scripts/config.example.sh scripts/config.sh && $EDITOR scripts/config.sh   # 2. fill it in
bash scripts/restore.sh check          # 3. read-only preflight

# 4. leave gateway mode first (docs/03), then confirm there is no residue:
bash scripts/check-gateway.sh          # must show the app on .../Application Support/Claude

# 5. quit Claude Desktop (⌘Q), then:
bash scripts/restore.sh test           # 20 sessions — reopen and verify
bash scripts/restore.sh all            # everything; tasks merged, all imported disabled

# 6. read task-merge-report-*.txt, then restore the enabled set in batches:
bash scripts/restore-enabled.sh --limit 5
```

> Step 4 is not optional. While the app is still in gateway mode you would be writing into the
> partition it is **not** reading, which looks exactly like a failed restore.

### What is preserved

| Asset | Preserved? | Notes |
|---|---|---|
| Conversation transcripts | ✅ | Already shared; the App just needs the metadata |
| Session list (titles, folders) | ✅ | Same-named files: the newer `lastActivityAt` wins; the displaced copy is kept in `replaced-sessions/` |
| Scheduled tasks / routines | ✅ | **Merged by id**, imported disabled; re-enable in batches |
| Skills, memory, `CLAUDE.md` | ✅ | Not account-scoped — nothing to do |
| Project files & git | ✅ | Never touched |
| Cowork sessions | ✅ | Separate partition, same technique (truncated dir names) |
| Cowork workspaces / memory / usage ledger | ❌ | Only `local_*` and `spaces` are copied; the script says so |
| Browser automation | ⚠️ | Paid plan → switch back to the official extension; otherwise keep the bridge. See docs/04 |
| Plugins | ❌ | Marketplace-synced; reinstall them |
| Published Artifacts / claude.ai chats | ❌ | Tied to the account; unrecoverable |

### Requirements

macOS, `bash`, `python3`, Claude Desktop.

### Contributing

Found a problem this kit doesn't warn about? That is the most useful thing you can report —
see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
