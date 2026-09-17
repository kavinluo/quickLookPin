# QuickLookPin

把 macOS 的 Quick Look 预览「钉」成一个个独立的置顶窗口，长时间阅读，同时不影响继续用 Finder。

> A macOS menu-bar utility that turns Quick Look previews into independent,
> always-on-top windows — so a preview can stay open while you keep browsing Finder.
> English summary at the bottom.

---

## 解决什么问题

macOS 的空格预览是一个**系统单例面板**，死死绑定 Finder 的当前选中项：

- 切到别的 Finder 窗口，它就消失
- 选中别的文件，里面的内容被直接换掉
- 想同时对着看两个文件？做不到

QuickLookPin 让你把预览**钉住**：一个文件一个窗口，各自独立，浮在最上层，
Finder 怎么折腾都不受影响。

## 怎么做到的

核心是 QuickLookUI 的 **`QLPreviewView`**。它是个普通 `NSView`，可以嵌进自建的
`NSWindow`，走的是和系统空格预览**完全同一套 Quick Look 管线**。

这带来一个关键好处：**你已经装的第三方 Quick Look 预览扩展照常生效**。
Markdown、源码高亮、各种格式插件，系统能预览什么，这里就能预览什么 ——
本项目不做任何格式白名单。

与系统 `QLPreviewPanel` 的根本区别：那个是**单例**，这个是**一窗一实例**。

## 功能

- **菜单栏常驻**（`LSUIElement`，没有 Dock 图标）
- **全局快捷键**唤起，可在偏好设置里自己录制
- **跟随模式**：新开的窗口跟随 Finder 选中项，在 Finder 里按上下键就切换内容
- **锁定**：点图钉锁定在当前文件，之后 Finder 再怎么切都不受影响
- **置顶可切换**，窗口可拖拽缩放，`⌘W` 关闭
- **跟随所有 Space**（`collectionBehavior`）
- **多窗口层叠偏移**，不会完全重合
- **文件被外部修改时自动刷新**预览
- **不劫持空格键**，系统原本的空格预览行为完全不受影响
- **不需要「辅助功能」权限**

## 环境要求

- macOS 13 及以上
- Xcode Command Line Tools（只用 `swiftc`，不依赖 SwiftPM / Xcode 工程 / 任何第三方库）

## 安装

### 方式一：下载现成的 App

到 [Releases](https://github.com/kavinluo/quickLookPin/releases) 下载
`QuickLookPin-<版本>-universal.zip`，解压后把 `QuickLookPin.app` 拖进「应用程序」。

通用二进制，Apple Silicon 和 Intel Mac 都能跑。

> ### ⚠️ 首次打开会被 Gatekeeper 拦住
>
> **这个 App 没有经过 Apple 公证**（公证需要付费的 Apple Developer 账号）。
> 所以从网上下载后第一次打开，macOS 会提示「无法验证此 App 是否包含恶意软件」
> 并拒绝启动。这是未公证 App 的统一待遇，不代表它有问题 ——
> 源码全在这个仓库里，你可以自己审、自己编。
>
> **放行办法（二选一）**
>
> 1. 双击一次（会被拒绝）→ 打开「系统设置 → 隐私与安全性」→
>    下拉找到「已阻止 QuickLookPin 的使用」→ 点「**仍要打开**」→ 再确认一次。
>
> 2. 或者直接用命令行去掉隔离标记：
>
>    ```bash
>    xattr -dr com.apple.quarantine /Applications/QuickLookPin.app
>    ```
>
> 注意：在 macOS 15 上，过去那招「右键 → 打开」**已经不管用了**，
> 必须走上面两条路之一。
>
> 介意的话就用下面的方式二，自己编译一份，完全不会遇到这个问题。

### 方式二：自己编译（推荐给开发者）

```bash
git clone https://github.com/kavinluo/quickLookPin.git
cd quickLookPin/QuickLookPin
./build.sh run
```

自己编译出来的 App 不带隔离标记，直接就能用。

## 构建

```bash
cd QuickLookPin
./build.sh              # 本机架构构建（开发用，最快）
./build.sh run          # 构建并启动
./build.sh universal    # 通用二进制 arm64 + x86_64（发布用）

./release.sh v0.1.0     # 构建通用二进制并打包成 zip，打印 SHA256
```

产物：`QuickLookPin/build/QuickLookPin.app`

`build.sh` 直接用 `swiftc` 编译再手工组装 bundle，最后做 **ad-hoc 签名**。

> ad-hoc 签名 ≠ Developer ID 签名 ≠ 公证，三者是递进的。ad-hoc 只能保证
> 本机 TCC 授权记账稳定；要让别人下载后无警告打开，必须做**公证**。
> `release.sh` 的注释里写了补公证需要加哪几行。

## 需要授予的权限

| 权限 | 何时触发 | 用途 |
|------|---------|------|
| **自动化 → Finder** | 第一次按快捷键 | 用 AppleScript 读取 Finder 当前选中项 |

拒绝之后可以到「系统设置 → 隐私与安全性 → 自动化」重新勾选。

**不需要**「辅助功能」权限：全局快捷键走 Carbon `RegisterEventHotKey`，
刻意避开了需要辅助功能授权的 `NSEvent` 全局监听。

**不需要**「屏幕录制」权限。

## 使用

1. 在 Finder 里选中文件，按快捷键 → 打开一个**跟随窗**
2. 在 Finder 里按上下键换选中项，窗口内容跟着切
3. 想留住某个文件 → 点**图钉**锁定，然后再按快捷键开下一个

同一时刻只维持一个跟随窗；已有未锁定的跟随窗时，按快捷键只会把它拉到前面。

标题栏右端**两个按钮各管一件事**：

| 按钮 | 管什么 |
|---|---|
| 📌 图钉 | **跟随 / 锁定**（内容层面）。跟随中标题显示 `◎ 跟随 ·`，锁定后显示 `📌` |
| ⬆️ 方块箭头 | **置顶 / 普通**（窗口层级） |

> ⚠️ **选快捷键时请避开空格键**，原因见下面「Finder 会吞掉空格键」。

---

## 工程笔记

开发过程中撞到的几个坑，都有实测数据，写在这里供参考。

### `QLPreviewView` 必须用 `.normal`，不能用 `.compact`

`.compact` 只会显示一张「白纸折角文档图标 + 缩略图」，**拿不到预览扩展的完整渲染结果**。
只有 `.normal` 才会走完整管线。

### 缩略图管线和预览管线是两回事

用 `qlmanage -t` 生成缩略图来判断「预览能不能用」是**错的**。很多扩展（例如 QLMarkdown）
只注册 `com.apple.quicklook.preview` 扩展点，没有 thumbnail 扩展，
于是缩略图走系统文本兜底、显示为纯文本，而预览其实完全正常。

### `RegisterEventHotKey` 对「已被占用的组合」也返回 `noErr`

这是最坑的一条。如果目标组合已被系统快捷键占用，注册**照样成功**，
但按键会被系统先截走，App 永远收不到 —— 表现是「日志说注册成功，按下去毫无反应，
连权限弹框都不出现」。**光看 `OSStatus` 检测不出这种冲突。**

`SystemHotKeyConflict.swift` 的做法是注册后另外查一遍 `com.apple.symbolichotkeys`，
发现冲突就在菜单栏和偏好设置里明确报警。

### Finder 会吞掉空格键，连带修饰键一起

即使系统层面没有冲突，**在 Finder 前台按 `⌃Space` 依然只会弹出系统自带的 Quick Look**。
原因是 Finder 自己对空格键的处理**忽略 Control 修饰符**，直接当裸空格处理，
在 Carbon 热键之前就把事件消费掉了。

所以任何「Space + 修饰键」的组合，只要指望在 Finder 前台触发，都不可靠。

### `FileWatcher` 的 `.attrib` 自触发死循环

监视文件变更时如果掩码里带 `.attrib` 且收到事件就无条件刷新，会形成死循环：
Quick Look 预览文件时系统和扩展本身会碰文件的扩展属性 → 触发 `.attrib` →
`refreshPreviewItem()` → 又碰属性 → 再次触发。表现为**预览窗口持续闪烁**。

实测（14 秒、全程无人碰文件）：

| | 文件事件 | 刷新次数 |
|---|---|---|
| 修复前 | 36 | 35 |
| 修复后 | 0 | 0 |

两道防线：掩码**不含 `.attrib`**；收到事件后 `stat` 一次，
拿 `(mtime, size, inode)` 和上次比，**一样就直接丢弃**。第二道是关键。

### `NSScreen.main` 不是「主显示器」

它的语义是「**键盘焦点所在的屏幕**」。多显示器下用它定位新窗口，会把窗口甩到
用户没在看的那块屏上。本项目改用「**鼠标所在的那块屏**」。

### 跟随模式只能轮询

Finder 没有提供「选中项变化」的公开通知，AppleScript 只能主动问。
想要事件驱动就得上 `AXObserver`，那需要辅助功能权限。

收敛手段：只在**存在跟随窗**时才启动轮询；只在 **Finder 处于前台**时才真正发 Apple Event。

> 副作用：**点一下预览窗口，跟随就会暂停** —— 前台变成了 QuickLookPin 自己，
> 轮询随即空转，直到焦点交回 Finder。想滚动阅读时，正确做法是**先点图钉锁定**。

---

## 性能

测量方法：**累计 CPU 时间**（`ps -o time`）与进程自报的 `phys_footprint`。
不要用 `top -l N` 瞬时采样做这类测量 —— 机器有负载时极不可靠，
实测曾把「什么都不做的空闲进程」测成 3.49%，同组样本从 0.2% 跳到 16.3%。

### 内存

| 状态 | footprint |
|---|---|
| 空闲（无窗口） | **12.3 MB** |
| 开 4 个预览窗口 | ~27.8 MB |
| 全部关闭后 | **25.2 MB**（稳定不再上涨） |

`ps` 的 RSS 会大得多（首次预览后约 89 MB），因为它把 WebKit、QuickLookUI 这些
**共享映射的框架页**也算进去了。看占用以 `phys_footprint` 为准。

### CPU

| 状态 | 占用 |
|---|---|
| 空闲 | **0.000%** |
| 跟随轮询中（0.4s 间隔） | **0.800%** |

0.8% 是**上限**：切到别的 App 时轮询空转、开销归零。

### 修掉的一个内存泄漏

反复开关预览窗口时内存呈线性上涨。A/B 对照（10 轮 × 每轮 4 个窗口）：

| | 首轮关闭后 | 末轮关闭后 | 平均斜率 | 后半段/前半段斜率 |
|---|---|---|---|---|
| 修复前 | 24.00 MB | 29.20 MB | +0.578 MB/轮 | 0.86（几乎不放缓 = 线性泄漏） |
| 修复后 | 24.00 MB | 25.20 MB | +0.133 MB/轮 | **0.16（走平）** |

**根因**：窗口设了 `shouldCloseWithWindow = false`，`QLPreviewView` 于是不会自己收尾，
而代码里**从未调用它的 `close()`**。修复就是在 `windowWillClose` 里显式 `preview.close()`。

顺带记一个**被证伪的猜测**：最初怀疑是 `QuickLookUIService.xpc` 进程泄漏（预览是跨进程渲染的）。
实测不成立 —— 杀掉 App 后那些 XPC 进程一个都没死（系统共享、launchd 托管），
且开关 40 次预览窗口期间 XPC 进程数**始终不变**。泄漏完全发生在进程内。

---

## 当前状态

如实记录，不要当成「全都验过了」。

### 已验证

- 第三方 Quick Look 扩展在自建宿主里正常渲染（完整 Markdown 排版：标题、粗体、
  行内代码、分隔线、列表、语法高亮代码块、引用块、表格）
- 多窗口并存、各自独立、层叠偏移
- `LSUIElement` 生效，无 Dock 图标；菜单栏项正常
- 全局快捷键实按可用；偏好设置里的快捷键录制可用
- Finder 自动化授权后能正确取到选中项
- 文件被外部修改后预览自动刷新
- 闪烁 bug 已修（有上面那组 36/35 → 0/0 的数据）
- 内存与 CPU 数据见上
- 一条命令构建出可运行的 `.app`

### 未验证

- `⌘W` 关闭窗口
- 标题栏两个按钮的**点击行为**（按钮能正常渲染，但点击后的状态切换没有系统性测过）
- 窗口拖拽、缩放
- `collectionBehavior` 跨 Space 跟随
- 多显示器修复（改用「鼠标所在屏」后，没有在两块屏上做过区分验证）
- 跟随模式只有有限次数的通过记录，没有做过压力测试

## 已知限制

- **ad-hoc 签名会让 TCC 重新弹授权**。每次重建签名都会变，
  「自动化 → Finder」可能要重新授权一次。根治需要正式开发者证书。
- **不支持「鼠标点击 + 按键」的组合快捷键**。`RegisterEventHotKey` 只接受
  「修饰键 + 键盘按键」。要支持鼠标组合只能上 `CGEventTap` / `NSEvent` 全局监听，
  那需要辅助功能权限。
- **不能用裸空格做快捷键**。不带修饰键的 Space 会导致在任何 App 里打空格都触发它；
  偏好设置的录制框会直接拒绝。
- 预览刷新依赖 `refreshPreviewItem()`，个别扩展可能不响应。
- 没有处理「文件被删除 / 移动后窗口该怎么办」。

## 调试入口

日志固定写在 `~/Library/Logs/QuickLookPin.log`（stderr 被重定向过去，
所以双击、`open`、命令行启动都能取到）。

> 注意：ad-hoc 签名的 App，`log show` 抓不到它的 `NSLog`，别用那个排查。

```bash
BIN=QuickLookPin/build/QuickLookPin.app/Contents/MacOS/QuickLookPin

# 绕开 Finder 和自动化权限，直接开锁定窗口
"$BIN" --pin ~/some/file.md

# 跟随模式自测：用 App 自己的 Apple Event 权限切换 Finder 选中项并自动校验
# 屏幕锁定时会直接中止（Finder 无法被激活，测了没意义）
"$BIN" --follow-test <文件夹> <文件1> <文件2> <文件3>

# 内存自测：反复开关窗口 N 轮，记录 phys_footprint
# 判据：各轮「全部关闭后」应走平；持续线性上涨就是泄漏
"$BIN" --mem-test 10 <文件1> <文件2> <文件3> <文件4>

# 轮询开销基准：开跟随窗后静置，用于干净测量轮询本身的 CPU
"$BIN" --poll-bench ~/some/file.md 55
```

## 目录结构

```
quicklook-pin/
  spike.swift        技术验证：单窗口，验证第三方扩展能否在自建宿主里加载
  spike2.swift       技术验证：多窗口独立性 + .normal/.compact 差异
  test.md, test2.md  测试用素材
  run.command        跑 spike 的一键脚本
  QuickLookPin/
    build.sh                             一条命令构建 .app
    Resources/Info.plist                 LSUIElement / NSAppleEventsUsageDescription
    Sources/
      main.swift                         入口 + stderr 重定向到日志文件
      AppDelegate.swift                  菜单栏、热键接线、窗口与跟随窗生命周期
      Settings.swift                     HotKeySpec + UserDefaults 偏好
      HotKeyManager.swift                Carbon RegisterEventHotKey 封装
      SystemHotKeyConflict.swift         查 symbolichotkeys，识别「注册成功但被占用」
      FinderSelection.swift              AppleScript 读取 Finder 选中项
      FinderSelectionWatcher.swift       轮询选中项，驱动跟随模式
      FileWatcher.swift                  DispatchSource 监视文件变更（带内容签名校验）
      PinnedPreviewWindowController.swift 预览窗口（跟随/锁定 + 置顶/普通）
      PreferencesWindowController.swift  偏好设置 + 快捷键录制
      MemoryReport.swift                 读取自身 phys_footprint
```

---

## English

**QuickLookPin** turns macOS Quick Look previews into independent, always-on-top
windows. The system's spacebar preview is a singleton panel bound to the current
Finder selection — switch windows or change selection and it disappears or swaps
its content. QuickLookPin lets you pin a preview so it stays put.

It embeds `QLPreviewView` (QuickLookUI) in its own `NSWindow`. Because that's the
same Quick Look pipeline the system panel uses, **any third-party Quick Look
preview extension you already have installed keeps working** — there's no format
whitelist.

**Highlights**

- Menu-bar only (`LSUIElement`), no Dock icon
- Configurable global hotkey via Carbon `RegisterEventHotKey` — **no Accessibility
  permission required**
- *Follow mode*: the window tracks the Finder selection (arrow keys switch content);
  click the pin to lock it to a file
- Floating level toggle, all-Spaces, cascade offsets, `⌘W` to close
- Live refresh when the file changes on disk
- Does **not** hijack the spacebar; the system preview keeps working

**Requirements**: macOS 13+, Xcode Command Line Tools. No SwiftPM, no Xcode
project, no third-party dependencies.

**Build**: `cd QuickLookPin && ./build.sh` → `QuickLookPin/build/QuickLookPin.app`

**Permissions**: only *Automation → Finder* (to read the current selection).

See the 工程笔记 / 性能 sections above for measured numbers and a write-up of the
non-obvious macOS pitfalls hit along the way (hotkey registration silently
succeeding on occupied combos, Finder swallowing the spacebar, a `DispatchSource`
`.attrib` feedback loop causing preview flicker, and a `QLPreviewView` leak from a
missing `close()`).

## License

[MIT](LICENSE)
