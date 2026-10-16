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
所以这个仓库**不覆盖**，它按 id **合并**：两边都有的以网关侧为准，只在账号侧有的原样保留，
连它的启用状态都不动。

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
git clone <本仓库> && cd claude-restore-kit

bash scripts/find-partitions.sh        # 1. 找源（Claude-3p）和目标（Claude）；存好启用清单
cp scripts/config.example.sh scripts/config.sh && $EDITOR scripts/config.sh   # 2. 填配置
bash scripts/restore.sh check          # 3. 只读预检（Claude 开着也能跑）

# 4. 完全退出 Claude Desktop（⌘Q），然后：
bash scripts/restore.sh test           # 只搬 20 条，重开 Claude 肉眼确认
bash scripts/restore.sh all            # 全量；任务按 id 合并，且全部停用

# 5. 重开 Claude，先查网关残留，再分批恢复启用：
bash scripts/check-gateway.sh
bash scripts/restore-enabled.sh --dry-run
bash scripts/restore-enabled.sh --limit 5
```

### 什么能搬回来

| 资产 | 搬得回来？ | 说明 |
|---|---|---|
| 对话正文 | ✅ | 本来就共享，App 只差元数据 |
| 会话列表（标题、文件夹分组） | ✅ | 把 `local_*.json` 复制进账号分区 |
| 定时任务 / Routine | ✅ | **按 id 合并**，停用状态导入；之后分批恢复 |
| 技能、记忆、`CLAUDE.md` | ✅ | 不按账号隔离，什么都不用做 |
| 项目文件与 git | ✅ | 从头到尾没碰 |
| Cowork 会话 + 工作区 | ✅ | 独立分区，同样的方法（注意目录名是截断的） |
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
routines. So this kit **merges** rather than replaces: ids present on both sides are updated
from the gateway, ids that exist only in the account are left completely alone — including
their enabled state.

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
git clone <this repo> && cd claude-restore-kit

bash scripts/find-partitions.sh        # 1. find source (Claude-3p) and target (Claude)
cp scripts/config.example.sh scripts/config.sh && $EDITOR scripts/config.sh   # 2. fill it in
bash scripts/restore.sh check          # 3. read-only preflight

# 4. quit Claude Desktop (⌘Q), then:
bash scripts/restore.sh test           # 20 sessions — reopen and verify
bash scripts/restore.sh all            # everything; tasks merged, all imported disabled

# 5. reopen Claude, check for gateway residue, then restore the enabled set in batches:
bash scripts/check-gateway.sh
bash scripts/restore-enabled.sh --limit 5
```

### What is preserved

| Asset | Preserved? | Notes |
|---|---|---|
| Conversation transcripts | ✅ | Already shared; the App just needs the metadata |
| Session list (titles, folders) | ✅ | Copy `local_*.json` into the account partition |
| Scheduled tasks / routines | ✅ | **Merged by id**, imported disabled; re-enable in batches |
| Skills, memory, `CLAUDE.md` | ✅ | Not account-scoped — nothing to do |
| Project files & git | ✅ | Never touched |
| Cowork sessions + workspaces | ✅ | Separate partition, same technique (truncated dir names) |
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
