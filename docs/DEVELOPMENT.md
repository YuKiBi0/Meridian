# 开发

仓库分三部分：

| 目录 | 内容 | 技术 |
| --- | --- | --- |
| `server/` | 子午服务 `meridian-server` | Go 1.22+，`net/http`，pgx，SSE |
| `console/` | 子午控制台 | Vue 3 + Vite + TypeScript，打包后嵌进服务端 |
| `client/` | 子午客户端 | Flutter（Windows 桌面） |

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

需要 Flutter stable 和 Windows 上的 Visual Studio（含「使用 C++ 的桌面开发」）。

```sh
cd client
flutter pub get
flutter run -d windows
flutter build windows --release   # 输出在 build/windows/x64/runner/Release
```

测试：

```sh
flutter analyze
flutter test test/core_test.dart test/geometry_test.dart test/colors_test.dart
flutter test integration_test -d windows   # 只能在 Windows 上运行：驱动真实窗口切换样式与贴边
```

托盘图标与应用图标由 `tool/gen_icons.sh` 生成（需要 `rsvg-convert` 和 ImageMagick）。

## 分支与发布

- 每个功能从 `develop` 开 `feature/*` 分支，通过 PR 合回 `develop`。
- 发布时把 `develop` 合到 `main`，打 `v*` 标签；`client-windows` 流水线会构建 Windows 包并附到 GitHub Release。
- 版本代号按二十四节气顺序排列，见 [DESIGN](DESIGN.md) 4.3。
- 完整的发版步骤与 `scripts/release.sh` 用法见 [发版](RELEASING.md)。
