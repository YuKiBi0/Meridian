# 部署

子午服务是一个 Go 程序，控制台已经打包在里面，数据存在 PostgreSQL。推荐用仓库自带的 Docker Compose 部署，再由宿主机的 nginx 反向代理到一个子路径（默认 `/meridian`）。

## 1. 准备配置

```sh
cp deploy/.env.example deploy/.env
```

编辑 `deploy/.env`：

| 变量 | 说明 |
| --- | --- |
| `POSTGRES_PASSWORD` | 数据库密码。建议用 `openssl rand -hex 24` 生成 |
| `MERIDIAN_ADMIN_TOKEN` | 控制台登录口令，至少 16 个字符 |
| `MERIDIAN_BASE_PATH` | 对外的子路径，默认 `/meridian`；放在域名根路径时留空 |
| `MERIDIAN_PORT` | 宿主机上监听的端口，默认 `8090`，只绑定 `127.0.0.1` |
| `MERIDIAN_VERSION` | 镜像标签，也是 `meridian-server version` 输出的版本 |
| `TZ` | 时区，只影响日志与操作记录的显示 |

## 2. 启动

```sh
docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build
```

会启动两个容器：`db`（PostgreSQL 17）和 `server`（子午服务）。数据库表在服务启动时自动迁移。

检查：

```sh
curl http://127.0.0.1:8090/meridian/healthz   # {"status":"ok"}
```

## 3. 反向代理

把 [`deploy/nginx/meridian.conf`](../deploy/nginx/meridian.conf) 放进站点的 `server { … }` 里（`include` 或直接粘贴），然后 `nginx -t && nginx -s reload`。

这份配置里有两点不能省：

- **`proxy_buffering off`**：状态是用 SSE 实时推送的，被 nginx 缓冲就会卡住。
- **`location ^~ /meridian/`**：`^~` 让这个前缀优先于站点里常见的 `~ .*\.(js|css)$` 之类的正则 location，否则控制台的静态资源会被别的规则截走。

服务会自己处理 `/meridian` 前缀，nginx 不要剥掉它。

## 4. 使用

- 控制台：`https://<你的域名>/meridian/`，用 `MERIDIAN_ADMIN_TOKEN` 登录，新建一个房间。
- 客户端里填写的房间地址：在控制台的房间页复制「客户端地址」，形如 `https://<你的域名>/meridian/?r=<房间 id>`。

从 1.0 升级时，原来的倒计时会变成一个名为「默认房间」的房间，进行中的一轮不受影响；1.0 客户端需要升级，并改填带 `?r=` 的房间地址。

## 升级

```sh
git pull
# 按需修改 deploy/.env 里的 MERIDIAN_VERSION
docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build
```

正在进行的倒计时会在重启后按原本的结束时刻恢复；重启期间跨过的提醒不会补发。

## 其他环境变量

直接运行二进制或自定义部署时可用：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MERIDIAN_ADDR` | `:8080` | 监听地址 |
| `MERIDIAN_DATABASE_URL` | — | PostgreSQL 连接串，必填 |
| `MERIDIAN_COOKIE_SECURE` | `true` | 本地 http 调试时设为 `false` |
| `MERIDIAN_TRUSTED_PROXY` | `127.0.0.1/32,172.16.0.0/12` | 信任其 `X-Forwarded-For` 的代理网段，用于操作记录里的来源 IP |

接口与协议见 [PRD](PRD.md) 第 9 章，部署架构见第 11 章。
