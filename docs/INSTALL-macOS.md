# 在 Mac 上安装子午

子午没有购买苹果开发者签名，所以 macOS 第一次打开时会拦一下。下面的步骤只需做一次，之后它和普通应用一样。

> 支持 macOS 12 及以上，Intel 与 Apple 芯片的 Mac 都可以用。「开机启动」需要 macOS 13 及以上。

## 1. 下载并拖进「应用程序」

1. 在 [Releases](https://github.com/YuKiBi0/Meridian/releases) 页面找到附有 `Meridian-macos.dmg` 的最新版本（目前是 [v1.2.0](https://github.com/YuKiBi0/Meridian/releases/tag/v1.2.0)），下载它。Mac 包不随每次发布构建。
2. 双击打开它，把 **Meridian** 拖到旁边的 **Applications（应用程序）** 文件夹上。
3. 在 Finder 侧边栏点 ⏏ 推出「Meridian」磁盘。

## 2. 第一次打开

先看一下系统版本：点屏幕左上角  →「关于本机」。

### macOS 15 及以上（Sequoia、Tahoe）

1. 打开「应用程序」文件夹，**双击 Meridian**。
   系统会弹出「未打开“Meridian”」，说 Apple 无法验证它是否包含恶意软件。点 **完成**，不要点「移到废纸篓」。
2. 打开 **系统设置** → 左侧 **隐私与安全性**，一直往下滚到「安全性」一节。
   会看到「已阻止“Meridian”以保护 Mac」，点旁边的 **仍要打开**，再用密码或触控 ID 确认。
3. 系统会再问一次是否打开，点 **仍要打开**。

「仍要打开」按钮只在第 1 步之后约一小时内出现。没看到的话，回到第 1 步再双击一次。

### macOS 14 及更早（Sonoma、Ventura、Monterey）

1. 打开「应用程序」文件夹，**按住 Control 键点 Meridian**（或用两根手指点触控板），选 **打开**。
2. 弹窗里点 **打开**。

## 3. 找到它

子午打开后**没有 Dock 图标**，它住在屏幕右上角的菜单栏里：一个中间有竖线的小圆圈。点它可以切换样式、贴边位置，打开设置或退出。

第一次打开会显示「房间地址」输入框，填入控制台里复制的客户端地址（形如 `https://example/meridian?r=…`）即可。

## 遇到问题

**提示「已损坏，无法打开」或「应该移到废纸篓」。** 通常是下载过程中文件被改动了，或者用了别的解压 / 下载工具。先重新下载 DMG 再试一遍。仍然不行的话，打开「终端」（在「应用程序 → 实用工具」里），粘贴下面这行并回车：

```sh
xattr -dr com.apple.quarantine /Applications/Meridian.app
```

它去掉的是 macOS 给“从网上下载的文件”打的标记，执行后就能直接双击打开。

**「隐私与安全性」里没有「仍要打开」。** 先双击 Meridian 被拦一次，再去看；按钮只在被拦之后一段时间内出现。

**开启了「开机启动」但没生效。** 打开 系统设置 → 通用 → 登录项与扩展，确认 Meridian 在列表里并已打开。Meridian 需要放在「应用程序」文件夹里才能登记为登录项。

**卸载。** 在菜单栏图标里选「退出」，把「应用程序」里的 Meridian 拖进废纸篓。设置保存在 `~/Library/Preferences/io.github.yukibi0.meridian.plist`，也可以一并删除。

## 为什么会被拦

macOS 只直接放行经过苹果公证的应用，公证需要每年付费的 Apple Developer Program 账号。子午的 macOS 包是 GitHub Actions 从[公开源码](../.github/workflows/client-macos.yml)构建的，只做了本地签名（ad hoc），所以第一次需要你手动确认一次。以后接入开发者账号做公证，这一步就会消失。

---

# Installing Meridian on a Mac

Meridian is not signed with a paid Apple developer certificate, so macOS blocks the first launch. You only do this once. Requires macOS 12 or later on Intel or Apple silicon; launch at startup needs macOS 13.

1. Download `Meridian-macos.dmg` from the newest release that has one (currently [v1.2.0](https://github.com/YuKiBi0/Meridian/releases/tag/v1.2.0)), open it and drag **Meridian** onto **Applications**.
2. **macOS 15 and later:** double-click Meridian in Applications and click **Done**. Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to the Meridian message and confirm with your password. Click **Open Anyway** once more.
   **macOS 14 and earlier:** Control-click Meridian in Applications, choose **Open**, then click **Open**.
3. Meridian has no Dock icon. It lives in the menu bar as a small circle with a vertical line.

If macOS says the app is damaged, download it again. If it still fails, run `xattr -dr com.apple.quarantine /Applications/Meridian.app` in Terminal.
