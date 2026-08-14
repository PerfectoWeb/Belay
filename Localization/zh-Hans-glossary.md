# zh-Hans terminology

Settled before any translating started, which is what kept three separate passes
saying the same thing. **Use this for any string added later**: a new label
translated from scratch is how a localisation drifts, and drift in a
twelve-word interface is visible.

The three that matter most, and why, because each has an obvious wrong answer:

- **agent is 智能体, never 代理.** 代理 is the Chinese for a network proxy, and
  this app talks about network requests, permissions and local listeners a few
  strings away.
- **Always On is 常开, never 常亮.** 常亮 promises the *screen* stays lit.
  Keeping the display awake is a separate option, off by default, and the
  welcome text says outright that the display may sleep without interrupting
  anything.
- **"saved" in "runs saved" is 保住, never 保存.** It means rescued from being
  killed by sleep, not written to disk. 保存 appears exactly once in the whole
  file, in "Belay's saved permission", where it really does mean stored.

The climbing metaphor does not cross over: hold, holding and keep awake all
become 保持唤醒, which is what Apple uses. Chinese has no everyday verb doing
both jobs, and the real climbing term reads as "ensure" in ordinary Chinese.

| English | 中文 | |
|---|---|---|

| Belay (app name) | Belay | Stays Latin everywhere per rule 3; never gloss it as 确保 or 保护 in running text, because a parenthetical explanation of the climbing pun would be the only place the metaphor exists in Chinese. |
| keep awake / stay awake / awake (state) | 保持唤醒 | Apple already ships 保持唤醒 (Apple Watch always-on display duration), so it is a platform word rather than an invention; 保持清醒 describes a person and 防止睡眠 forces a negative construction that breaks in the many positive strings such as “Keeping your Mac awake”. |
| hold / holding / keep holding | 保持唤醒 | Deliberately the same verb as “keep awake”: the shipping English already replaced almost every “hold” with “keep awake”, so Chinese should not resurrect a second verb for one action. |
| While holding | 保持唤醒期间 | This is a settings section header covering what happens during a hold, so a time-span noun (期间) is needed rather than a verb phrase. |
| Belay stopped holding | Belay 已停止保持唤醒 | Notification title; 已停止 rather than 停止了 keeps it a status statement, and never 已放开 or 已释放, which read as memory release. |
| let go / release / let the Mac sleep | 让 Mac 进入睡眠 | State the consequence, not the grip; 释放 means freeing a resource and 放开 is physical, so both would be read literally. |
| sleep (verb / noun) | 睡眠 / 进入睡眠 | macOS itself uses 睡眠 in the Apple menu and battery settings, so no other word is admissible; the verb always takes 进入 (Mac 进入睡眠), never 睡觉. |
| asleep / went to sleep | 已进入睡眠 | Chinese has no adjectival “asleep”; the perfective 已进入睡眠 carries it without adding a word. |
| system sleep | 系统睡眠 | Used only when it must be contrasted with display sleep; elsewhere plain 睡眠 is enough and shorter. |
| display sleep / let the display sleep | 显示器睡眠 / 让显示器进入睡眠 | Parallel to system sleep so the two settings read as a pair; 关闭显示器 (macOS battery pane wording) would wrongly imply Belay switches the screen off. |
| display | 显示器 | macOS System Settings uses 显示器 for this pane on Mac; 屏幕 is the iOS word and 显示屏 is hardware marketing. |
| keep the display awake | 让显示器保持唤醒 | Reuses 保持唤醒 so the display option is visibly the same promise applied to a second thing. |
| idle | 空闲 | This is a status chip for a provider or agent that is running but doing nothing, which is 空闲; 闲置 describes an unused object and 不活跃 is the macOS phrase for the user being away, a different idea in this app. |
| grace period | 缓冲时间 | The word never appears in the interface (the label is “Wait before letting your Mac sleep”), so 缓冲时间 is the internal term and the visible label is 让 Mac 进入睡眠前的等待时间; 宽限期 is a billing and deadline word and would sound bureaucratic. |
| maximum awake time | 最长唤醒时间 | A duration cap takes 最长, not 最大; keep the same four-word shape in the notification, the panel line and the settings label so users recognise one feature. |
| awake time (statistics tile) | 唤醒时长 | Tile labels are nouns, and 时长 is the standard Chinese for an accumulated duration; the setting above keeps 时间 because it is a limit, not a total. |
| agent | 智能体 | 代理 is the Chinese word for proxy and would be read as a network proxy in an app that also talks about network requests and permissions; 智能体 is the settled mainland term for an autonomous AI worker and is what Chinese developers call Claude Code and its peers. |
| subagent | 子智能体 | Built on the parent term so the hierarchy is visible at a glance, as 子进程 is to 进程. |
| coding agent | 编程智能体 | Only where the English says “coding agent”; elsewhere plain 智能体 is enough and saves width. |
| session | 会话 | Standard across Apple and Chinese developer tooling; do not drift to 对话, which would describe the chat rather than the tracked unit. |
| active sessions | 活跃会话 | 活跃 rather than 活动, because 活动 collides with “activity” (folder activity) used elsewhere in the same screen. |
| run (one stretch of agent work) | 运行 | Counted as %lld 次运行; 任务 is reserved for “task” and 会话 for “session”, and using either here would erase a distinction the statistics screen depends on. |
| agent run | 智能体运行 | Full form only in the sentence-length statistics strings; the tiles drop 智能体 because the whole screen is about agents. |
| saved (a run rescued from sleep) | 保住 | 保存 means to store a file and would turn “saved %lld agent runs” into nonsense; 保住 is “kept from being lost”, which is exactly the claim. |
| runs saved | 保住的运行 | Tile label; keep the 的 so it reads as a count of runs rather than as a verb phrase. |
| runs watched | 监视的运行 | Same shape as the tile beside it, which is what makes the two numbers comparable at a glance. |
| longest run | 最长运行 | Matches 最长唤醒时间 in construction; no 的 here because the tile is already short. |
| turn (one Claude Code turn) | 轮次 | Appears once, in the Claude Code provider description; 轮次 keeps it distinct from both 运行 and 会话, which is the point of the sentence. |
| task | 任务 | Used only where the English says task (“when a long task finishes”, “between tasks”); do not let it spread onto 运行, even though the English uses the two loosely in the notifications pane. |
| work / working (agent is working) | 工作 / 工作中 | 工作中 is the status chip; 忙碌 would add an impatience the English does not have and 运行中 would collide with 运行 as a counted noun. |
| watch / watching | 监视 | 监视文件夹 is the established Chinese for a watch folder in professional tools, and 监视 stays visually far from 检测 (detection), whereas the softer 监测 differs from 检测 by one similar character and would be misread. |
| Start watching | 开始监视 | Welcome-screen primary button; four characters, and it names the action rather than the outcome, as the English does. |
| watch folder | 监视文件夹 | A folder Belay observes for changes, not a folder of watches; keep it as one noun phrase and never split it. |
| activity (folder activity) | 活动 | 文件夹活动 is the signal Belay reads; keep 活跃 for sessions so the two never blur. |
| detection | 检测 | The mechanism by which Belay decides an agent is working; 检测 is the platform-neutral technical word and is deliberately kept apart from 监视 (watch), which is what Belay does to a folder. |
| precise detection | 精确检测 | 精确 rather than 准确: the feature is about exact start and stop points, not about being correct more often. |
| detection status | 检测状态 | The English key was “Detection health”, but the shipped label is status, and 状态 matches the Ready / Idle / Working values shown under it. |
| provider | 来源 | A provider here is where activity signals come from, and 来源 is short enough for a settings tab beside 通用 and 通知; 提供方 is the dictionary answer but reads as machine translation in strings like “No providers available”. Use 检测来源 in body text where 来源 alone would be too vague. |
| preset | 预设 | 预设 is what Chinese developers expect for a ready-made configuration; Apple's 预置 survives mainly in Logic Pro and would look dated here. |
| hook | 钩子 | The settled Chinese for the concept; the literal JSON key hooks inside the Claude Code settings snippet stays Latin and must not be translated. |
| hook listener | 钩子监听器 | 监听器 is the standard for a local listener; 接收器 would suggest it receives files. |
| webhook | Webhook | Kept in Latin, as Chinese developer writing does; 网络钩子 would collide confusingly with 钩子 above. |
| process | 进程 | Platform word; “process %@” becomes 进程 %@ with a space before the placeholder. |
| signal | 信号 | “last signal %@ ago” becomes 上次信号在 %@ 前, keeping the placeholder between two short words so it cannot be reordered by accident. |
| tool (a coding tool Belay watches) | 工具 | Kept distinct from 智能体: the Providers pane calls the watched thing a tool, and a Chinese reader will accept 工具 as covering both a CLI and a folder rule. |
| mode | 模式 | Platform word; the three mode names below are always quoted with “ ” when they appear inside a sentence. |
| Auto | 自动 | Two characters, matching the other two mode names so the segmented control stays balanced. |
| Always On | 常开 | Not 常亮, which means the screen stays lit: keeping the display awake is a separate option that is off by default, so 常亮 would promise something the mode does not do. 常开 describes Belay staying on, which is what the mode is. |
| Off | 关闭 | Belay is off, not the Mac; the same word covers “turn it off” in the panel descriptions so users connect the switch to the mode. |
| Awake mode | 唤醒模式 | The accessible name of the mode control in the panel; keep 唤醒 so it ties to 保持唤醒 rather than becoming a bare 模式. |
| menu bar | 菜单栏 | macOS uses 菜单栏; never 状态栏, which is the iOS status bar. |
| panel | 面板 | Belay's menu bar popover; 弹出窗口 describes the mechanism rather than the thing, and the string “%@ panel” is an accessibility label where a noun is required. |
| assertion (power / sleep assertion) | 电源断言 | Correct for IOKit, but the shipping English deliberately removed it (“macOS couldn't keep the Mac awake”); do not reintroduce it into any visible string, use it only if a developer-facing log line demands it. |
| battery floor | 电量下限 | Internal term for the percentage at which Belay stops; the visible strings say 电量降至 %lld%% 时停止, because the English also avoids naming the concept. |
| battery (charge level) | 电量 | Apple separates 电池 (the hardware) from 电量 (the level), so “Battery reached %lld%%” is 电量降至 %lld%%, not 电池. |
| low battery | 电量低 | Predicative 电量低 in sentences, attributive 低电量 before a noun; both avoid the fixed term 低电量模式 below. |
| Low Power Mode | 低电量模式 | The exact macOS and iOS setting name; it must match System Settings character for character or users will not find it. |
| login item | 登录项 | The System Settings pane name; “Open Login Items…” becomes 打开“登录项”… so the user knows exactly which pane opens. |
| Open at login | 登录时打开 | The wording macOS itself uses for this checkbox; do not invent 开机启动, which describes a different Windows-flavoured concept. |
| Startup | 启动 | Section header only, kept to two characters against the neighbouring headers. |
| notification / notify | 通知 | Apple's word; “Notify me” is 通知我 and “Notify when …” is …时通知我, keeping the trigger before the verb as Chinese requires. |
| permission | 权限 | Covers both senses in this app, the macOS folder permission and the agent's own permission prompt (权限询问); the reader distinguishes them from context as in English. |
| Allow access / Grant access | 允许访问 | The English uses two verbs for one act; Chinese uses one, and 允许 is the verb on the macOS permission alert the user is about to see. |
| Skip for now | 暂时跳过 | 暂时 carries “for now” without implying the choice is permanent; 以后再说 would be too conversational for this voice. |
| Settings (Belay's own) | 设置 | macOS 13 and later renamed Preferences to Settings, and zh-Hans followed with 设置…; do not use 偏好设置. |
| System Settings | 系统设置 | The exact app name in macOS 13 and later; always quoted as “系统设置” when a sentence tells the user to open it. |
| Ready | 就绪 | Status value; 准备好了 is a sentence, and this is a chip. |
| Waiting for you | 等待回应 | As a status chip Chinese needs an object, and 回应 is what the agent is actually waiting for; in full sentences it becomes 智能体在等你回应. |
| Finished | 已完成 | 已 marks the completed state for the chip and the notification title alike; bare 完成 is the Done button and must stay separate. |
| Done (button) | 完成 | Apple's standard button label, deliberately distinct from the 已完成 status. |
| Fix (button) | 修复 | Two characters for a narrow inline button; 解决 would suggest the user does the work. |
| Remove | 移除 | Apple reserves 删除 for destroying data; Belay's Remove restores a backup, so 移除 is both accurate and less alarming. |
| Reset… (opens the confirmation) | 重置… | The button that asks; keep the single-character ellipsis … exactly as in English. |
| Erase (the destructive confirmation) | 清除 | 清除 for data inside an app; Apple's 抹掉 belongs to disks and devices and would sound disproportionate for a statistics reset. |
| Share | 共享 | Apple's share sheet is 共享 in zh-Hans; translators reflexively write 分享, which is the social-media word and would look off-platform. |
| Copy / Copied | 复制 / 已复制 | 已复制 for the transient confirmation, matching the 已 pattern used by the other completed states. |
| Star (on GitHub) | 加星标 | GitHub's own Chinese uses 星标; as a button the verb 加星标 is clearer than the bare noun and still three characters. |
| Statistics | 统计 | Window and tab title; 统计信息 is a description, not a title, and costs width the panel does not have. |
| update / software update | 更新 / 软件更新 | 软件更新 is the System Settings pane name and should appear in the section header; plain 更新 elsewhere. |
| update feed | 更新源 | 源 matches 来源 for providers and is the word Chinese package tooling uses for a feed. |
| away (from the keyboard) | 离开 | 你离开时 in sentences, 离开 alone in the compact statistics pair; 不在 would read as absent from the room and 离开电脑 wastes width. |
| tip / tipping (in-app) | 打赏 | 打赏 is what Chinese App Store apps call this; 小费 is a restaurant gratuity and would puzzle the reader. |
| Donate | 捐赠 | Kept separate from 打赏 because the About pane offers both and they link to different places. |
| project | 项目 | “Untitled project” becomes 未命名项目, matching Apple's 未命名 pattern. |
| App Store / Mac App Store | App Store / Mac App Store | Apple leaves both in Latin in zh-Hans; 应用商店 is the generic Android word and is wrong here. |
| tracking | 跟踪 | Apple's App Tracking Transparency uses 跟踪, so 无跟踪 for the About pane badge. |
| backup | 备份 | 带时间戳的备份 for “timestamped backup”; the timestamp modifier goes before the noun. |
| compact time units d / h / m / s | 天 / 时 / 分 / 秒 | The compact stat forms such as %lldd %@h become %lld 天 %@ 时; Chinese single-character units are as short as the Latin letters and read as Chinese, while the long forms 小时 分钟 are used only in the settings picker where there is room. |
