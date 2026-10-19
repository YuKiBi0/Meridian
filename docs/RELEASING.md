# 发版

一次发版分四步：改版本号 → 合到 `main` → 打标签发布 → 部署服务端。版本号相关的步骤都由 [`scripts/release.sh`](../scripts/release.sh) 完成。

## 版本号与代号

版本号用 `主.次.修`（[语义化版本](https://semver.org/lang/zh-CN/)）：

| 改动 | 升哪一位 | 例子 |
| --- | --- | --- |
| 只修 bug | 修订号 | `1.0.0` → `1.0.1` |
| 加功能，旧的用法不受影响 | 次版本号 | `1.0.1` → `1.1.0` |
| 不兼容的改动，例如协议变了，旧客户端连不上新服务 | 主版本号 | `1.1.0` → `2.0.0` |

每次对外发布（包括修复版本）按顺序取下一个节气作为代号（[DESIGN](DESIGN.md) 4.3），脚本会自动顺延：小满 → 芒种 → 夏至 → 小暑 → …… → 大寒 → 立春。

版本号写在下面这些地方，脚本会一起改，发布前也会检查它们是否一致：

| 文件 | 内容 |
| --- | --- |
| `client/pubspec.yaml` | `version: X.Y.Z+N`，构建号 `N` 每次加 1 |
| `client/lib/ui/l10n.dart` | 关于页的 `appVersion` 与中英文节气 |
| `console/package.json`、`package-lock.json` | 控制台版本 |
| `Dockerfile`、`deploy/docker-compose.yml`、`deploy/.env.example` | 服务端默认版本 |

## 1. 改版本号

在 `develop` 上开一个发版分支：

```sh
git checkout develop && git pull
git checkout -b chore/release-1.1.0
scripts/release.sh bump 1.1.0          # 代号自动取下一个节气
scripts/release.sh bump 1.1.0 芒种     # 也可以手动指定
```

然后在 [PRD](PRD.md) 第 14 章的里程碑表里补一行，提交、推送并开 PR 合到 `develop`：

```sh
git commit -am "chore: release v1.1.0 (Grain in Ear)"
git push -u origin chore/release-1.1.0
gh pr create --base develop --fill
```

## 2. 合到 `main`

确认 `develop` 上的 CI 全绿，从 `develop` 往 `main` 开 PR 并合并：

```sh
gh pr create --base main --head develop --title "Release v1.1.0" --body ""
```

## 3. 打标签并发布

```sh
git checkout main && git pull
scripts/release.sh publish             # 用合并过的 PR 自动生成发布说明
scripts/release.sh publish notes.md    # 或者用自己写的说明
```

脚本会：

1. 检查当前在 `main`、工作区干净、与 `origin/main` 一致、各处版本号相同、标签还不存在；
2. 确认后打带说明的标签 `vX.Y.Z` 并推送；
3. 创建标题为 `vX.Y.Z · 节气` 的 GitHub Release，并标为最新；
4. 等待 `client-windows` 流水线构建完成，确认 `Meridian-windows-x64.zip` 已附到 Release 上。

**Mac 包（可选）。** macOS runner 费用高，`client-macos` 不随推送或标签自动运行，最近一次构建的是 v1.2.0。需要给某个版本附上 DMG 时，在标签上手动运行，完成后 `Meridian-macos.dmg` 会附到该 Release：

```sh
gh workflow run client-macos.yml --ref vX.Y.Z
```

自己写说明时可以参考 [v1.0.0](https://github.com/YuKiBi0/Meridian/releases/tag/v1.0.0)：下载方式、新增与修复、已知限制。

## 4. 部署服务端

在服务器的仓库目录里：

```sh
scripts/release.sh deploy              # 部署最新的标签
scripts/release.sh deploy 1.1.0        # 部署指定版本，也可以用来回滚
```

脚本会把指定标签检出到一个临时目录里构建，所以当前仓库在哪个分支都没关系；它会把 `deploy/.env` 里的 `MERIDIAN_VERSION` 改成目标版本，然后重建并启动容器，等 `healthz` 返回正常后输出部署的版本。旧版本的镜像会保留在本机，回滚时多数构建步骤直接命中缓存。

## 发错了怎么办

还没人下载时，可以删掉重来：

```sh
gh release delete v1.1.0 --cleanup-tag --yes   # 删除 Release 和远程标签
git tag -d v1.1.0                              # 删除本地标签
```

已经有人下载过，就不要重复使用同一个版本号，修好后直接发下一个修复版本（例如 `v1.1.1`）。
