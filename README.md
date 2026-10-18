# Meridian

> 所有窗口，同一个现在。

子午是一个自部署的倒计时同步系统：服务器持有唯一的一个倒计时，任意多个窗口显示同一个剩余时间。操作者在控制台开始、暂停、延长、结束，所有窗口同时跟着变。

| 程序 | 目录 | 说明 |
| --- | --- | --- |
| 子午服务 `meridian-server` | `server/` | Go，SSE 推送，PostgreSQL 持久化，内嵌控制台 |
| 子午控制台 | `console/` | Vue 3 网页，操作倒计时、管理预设与提醒 |
| 子午 | `client/` | Flutter Windows 客户端，贴边、置顶、提醒卡片 |

文档：[产品需求](docs/PRD.md) · [设计理念](docs/DESIGN.md)

## 部署

```sh
cp deploy/.env.example deploy/.env        # 填入 POSTGRES_PASSWORD 与 MERIDIAN_ADMIN_TOKEN
docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build
```

服务只监听 `127.0.0.1:8090`，再由宿主机 nginx 反向代理。配置片段见 [`deploy/nginx/meridian.conf`](deploy/nginx/meridian.conf)：必须关闭 `proxy_buffering`，并用 `location ^~ /meridian/`。

部署后：

- 控制台：`https://<域名>/meridian/`，用 `MERIDIAN_ADMIN_TOKEN` 登录
- 客户端填写的服务器地址：`https://<域名>/meridian`

## 开发

```sh
# 数据库
docker run -d --name meridian-dev-pg -e POSTGRES_USER=meridian -e POSTGRES_PASSWORD=meridian \
  -e POSTGRES_DB=meridian -p 127.0.0.1:55432:5432 postgres:17-alpine

# 服务端
cd server
MERIDIAN_ADDR=127.0.0.1:18090 MERIDIAN_BASE_PATH=/meridian MERIDIAN_COOKIE_SECURE=false \
MERIDIAN_DATABASE_URL='postgres://meridian:meridian@127.0.0.1:55432/meridian?sslmode=disable' \
MERIDIAN_ADMIN_TOKEN=dev-token-0123456789 go run ./cmd/meridian-server

# 测试（集成测试需要数据库）
MERIDIAN_TEST_DATABASE_URL='postgres://meridian:meridian@127.0.0.1:55432/meridian?sslmode=disable' go test -p 1 ./...

# 控制台（http://localhost:5173/meridian/，接口代理到 18090）
cd console && npm install && npm run dev

# 把控制台打包进服务端
scripts/build-console.sh
```

## 设计说明

产品名取自子午线：一条人为约定的线，让不同地方的人共享同一个「现在」。客户端内部代号 Astrolabe（星盘），控制台内部代号 Observatory（天文台）。版本代号按二十四节气顺序排列，1.0 为小满。更多见 [DESIGN.md](docs/DESIGN.md)。

所有窗口，同一个现在。
