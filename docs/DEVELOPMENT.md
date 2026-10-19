# 开发

仓库分三部分：

| 目录 | 内容 | 技术 |
| --- | --- | --- |
| `server/` | 子午服务 `meridian-server` | Go 1.22+，`net/http`，pgx，SSE |
| `console/` | 子午控制台 | Vue 3 + Vite + TypeScript，打包后嵌进服务端 |
| `client/` | 子午客户端 | Flutter（Windows / macOS 桌面） |

产品需求见 [PRD](PRD.md)，视觉与用词规范见 [DESIGN](DESIGN.md)。

## 服务端

先起一个开发用的数据库：

```sh
docker run -d --name meridian-dev-pg -e POSTGRES_USER=meridian -e POSTGRES_PASSWORD=meridian \
  -e POSTGRES_DB=meridian -p 127.0.0.1:55432:5432 postgres:17-alpine
```

运行：

```sh
cd server
MERIDIAN_ADDR=127.0.0.1:18090 MERIDIAN_BASE_PATH=/meridian MERIDIAN_COOKIE_SECURE=false \
MERIDIAN_DATABASE_URL='postgres://meridian:meridian@127.0.0.1:55432/meridian?sslmode=disable' \
MERIDIAN_ADMIN_TOKEN=dev-token-0123456789 go run ./cmd/meridian-server
```

测试（API 集成测试需要数据库，会清空表，请用专门的开发库）：

```sh
MERIDIAN_TEST_DATABASE_URL='postgres://meridian:meridian@127.0.0.1:55432/meridian?sslmode=disable' \
  go test -p 1 ./...
```

## 控制台

```sh
cd console
npm install
npm run dev        # http://localhost:5173/meridian/ ，接口代理到 127.0.0.1:18090
npm test           # vitest
npm run build      # 类型检查 + 构建
```

把控制台打包进服务端（发布前需要）：

```sh
scripts/build-console.sh
```

## 客户端

需要 Flutter stable，以及 Windows 上的 Visual Studio（含「使用 C++ 的桌面开发」）或 Mac 上的 Xcode。

```sh
cd client
flutter pub get
flutter run -d windows            # 或 -d macos
flutter build windows --release   # 输出在 build/windows/x64/runner/Release
flutter build macos --release     # 输出在 build/macos/Build/Products/Release/Meridian.app
```

窗口的摆放、置顶、穿透与不抢焦点由各平台的原生代码实现，通过 `meridian/window` 通道调用：Windows 在 `windows/runner/flutter_window.cpp`，macOS 在 `macos/Runner/MainFlutterWindow.swift`（无边框、不激活的 NSPanel；坐标以点为单位、左上为原点，缩放固定为 1）。macOS 版只在菜单栏显示图标（`LSUIElement`），图标在运行时绘制。

测试：

```sh
flutter analyze
flutter test test/core_test.dart test/geometry_test.dart test/colors_test.dart
flutter test integration_test -d windows   # 或 -d macos：驱动真实窗口切换样式与贴边
```

Windows 托盘图标与两个平台的应用图标由 `tool/gen_icons.sh` 生成（需要 `rsvg-convert` 和 ImageMagick）。

## 分支与发布

- 每个功能从 `develop` 开 `feature/*` 分支，通过 PR 合回 `develop`。
- 发布时把 `develop` 合到 `main`，打 `v*` 标签；`client-windows` 流水线会构建 Windows 包并附到 GitHub Release。`client-macos` 只手动运行（macOS runner 费用高），在标签上运行即可把 DMG 附到该版本，见 [发版](RELEASING.md)。macOS 包没有开发者签名，只做本地签名（ad hoc），用户第一次打开需要手动放行，见 [Mac 安装说明](INSTALL-macOS.md)。
- 版本代号按二十四节气顺序排列，见 [DESIGN](DESIGN.md) 4.3。
- 完整的发版步骤与 `scripts/release.sh` 用法见 [发版](RELEASING.md)。
