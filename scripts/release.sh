#!/usr/bin/env bash
# Release helper. The full walkthrough is in docs/RELEASING.md.
#
#   scripts/release.sh bump <version> [codename]   on a release branch off develop
#   scripts/release.sh publish [notes.md]          on main, after develop is merged
#   scripts/release.sh deploy [version]            on the server, from any branch
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

# Solar terms in order (DESIGN 4.3). One per public release, fix releases included.
terms_zh=(立春 雨水 惊蛰 春分 清明 谷雨 立夏 小满 芒种 夏至 小暑 大暑
          立秋 处暑 白露 秋分 寒露 霜降 立冬 小雪 大雪 冬至 小寒 大寒)
terms_en=('Start of Spring' 'Rain Water' 'Awakening of Insects' 'Spring Equinox'
          'Pure Brightness' 'Grain Rain' 'Start of Summer' 'Grain Buds'
          'Grain in Ear' 'Summer Solstice' 'Minor Heat' 'Major Heat'
          'Start of Autumn' 'End of Heat' 'White Dew' 'Autumn Equinox'
          'Cold Dew' "Frost’s Descent" 'Start of Winter' 'Minor Snow'
          'Major Snow' 'Winter Solstice' 'Minor Cold' 'Major Cold')

l10n=client/lib/ui/l10n.dart

die() { echo "release: $*" >&2; exit 1; }
say() { printf '\033[1m%s\033[0m\n' "$*"; }

usage() {
  sed -n '4,6p' "$0" | sed 's/^# *//'
  exit 2
}

current_version() { sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' client/pubspec.yaml; }
current_build() { sed -n 's/^version: *[0-9.]*+\([0-9]*\).*/\1/p' client/pubspec.yaml; }
current_term() { grep -m1 'solarTerm:' "$l10n" | sed "s/.*'\(.*\)'.*/\1/"; }

term_index() {
  local i
  for i in "${!terms_zh[@]}"; do
    [ "${terms_zh[$i]}" = "$1" ] && { echo "$i"; return; }
  done
  die "未知的节气：$1"
}

# Replaces $2 with $3 in file $1 (literal strings); fails if $2 is absent.
replace() {
  grep -qF -- "$2" "$1" || die "$1 里找不到 $2"
  FROM=$2 TO=$3 perl -pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/g' "$1"
}

# Every place that carries the version must agree with pubspec.yaml.
check_versions() {
  local v=$1 bad=0
  check() { grep -qF -- "$2" "$1" || { echo "  $1 缺少 $2" >&2; bad=1; }; }
  check client/pubspec.yaml "version: $v+"
  check "$l10n" "appVersion = 'v$v'"
  check console/package.json "\"version\": \"$v\""
  check Dockerfile "ARG VERSION=$v"
  check deploy/docker-compose.yml "\${MERIDIAN_VERSION:-$v}"
  check deploy/.env.example "MERIDIAN_VERSION=$v"
  [ "$(jq -r .version console/package-lock.json)" = "$v" ] || { echo "  console/package-lock.json 版本不是 $v" >&2; bad=1; }
  [ $bad = 0 ] || die "版本号不一致，请先运行 scripts/release.sh bump $v"
}

cmd_bump() {
  local new=${1:-} cur cur_zh cur_en i next_zh next_en build
  [[ $new =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "版本号要写成 X.Y.Z，例如 1.1.0"
  cur=$(current_version)
  if [ "$new" = "$cur" ] || [ "$(printf '%s\n%s\n' "$cur" "$new" | sort -V | tail -1)" != "$new" ]; then
    die "新版本 $new 必须比当前的 $cur 大"
  fi

  cur_zh=$(current_term)
  i=$(term_index "$cur_zh")
  cur_en=${terms_en[$i]}
  if [ -n "${2:-}" ]; then
    i=$(term_index "$2")
  else
    i=$(( (i + 1) % 24 ))
  fi
  next_zh=${terms_zh[$i]}
  next_en=${terms_en[$i]}
  build=$(( $(current_build) + 1 ))

  say "v$cur · $cur_zh → v$new · $next_zh ($next_en)"

  replace client/pubspec.yaml "version: $cur+$(current_build)" "version: $new+$build"
  replace "$l10n" "appVersion = 'v$cur'" "appVersion = 'v$new'"
  replace "$l10n" "solarTerm: '$cur_zh'" "solarTerm: '$next_zh'"
  replace "$l10n" "solarTerm: '$cur_en'" "solarTerm: '$next_en'"
  replace Dockerfile "ARG VERSION=$cur" "ARG VERSION=$new"
  replace deploy/docker-compose.yml "\${MERIDIAN_VERSION:-$cur}" "\${MERIDIAN_VERSION:-$new}"
  replace deploy/.env.example "MERIDIAN_VERSION=$cur" "MERIDIAN_VERSION=$new"
  (cd console && npm version "$new" --no-git-tag-version --allow-same-version >/dev/null)
  check_versions "$new"

  git --no-pager diff --stat
  cat <<EOF

接下来：
  1. 在 docs/PRD.md 第 14 章的里程碑表里补一行 v$new · $next_zh
  2. git commit -am "chore: release v$new ($next_en)"
  3. 推送分支，开 PR 合到 develop；再从 develop 开 PR 合到 main
  4. 在 main 上运行 scripts/release.sh publish
EOF
}

cmd_publish() {
  local notes=${1:-} v tag zh en
  command -v gh >/dev/null || die "需要 gh（GitHub CLI）"
  [ -z "$notes" ] || [ -f "$notes" ] || die "找不到发布说明 $notes"
  [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "请在 main 分支上发布"
  [ -z "$(git status --porcelain)" ] || die "工作区有未提交的改动"
  git fetch -q origin main --tags
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "本地 main 与 origin/main 不一致，先 git pull"

  v=$(current_version)
  tag=v$v
  check_versions "$v"
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "标签 $tag 已存在"
  zh=$(current_term)
  en=${terms_en[$(term_index "$zh")]}

  say "将在 main@$(git rev-parse --short HEAD) 发布 $tag · $zh ($en)"
  read -r -p "继续？[y/N] " ok
  [ "$ok" = y ] || [ "$ok" = Y ] || die "已取消"

  git tag -a "$tag" -m "$tag · $zh ($en)"
  git push -q origin "$tag"
  if [ -n "$notes" ]; then
    gh release create "$tag" --verify-tag --latest --title "$tag · $zh" --notes-file "$notes"
  else
    gh release create "$tag" --verify-tag --latest --title "$tag · $zh" --generate-notes
  fi

  wait_client "$tag" client-windows Meridian-windows-x64.zip
  say "已发布：$(gh release view "$tag" --json url --jq .url)"
}

# Waits for a client workflow on the tag and checks its release asset.
wait_client() {
  local tag=$1 workflow=$2 file=$3 run='' asset
  say "等待 $workflow 构建 $file……"
  for _ in $(seq 30); do
    run=$(gh run list --workflow "$workflow.yml" --branch "$tag" --limit 1 --json databaseId --jq '.[0].databaseId // empty')
    [ -n "$run" ] && break
    sleep 5
  done
  [ -n "$run" ] || die "没找到 $tag 的 $workflow 构建，去 Actions 页面看一下"
  gh run watch "$run" --exit-status --interval 30 >/dev/null || die "构建失败：gh run view $run --log-failed"

  asset=$(gh release view "$tag" --json assets --jq '.assets[].name' | grep -cx "$file" || true)
  [ "$asset" = 1 ] || die "Release 上没有 $file"
}

cmd_deploy() {
  local v=${1:-} tag env=deploy/.env port base url
  [ -f "$env" ] || die "找不到 $env，先按 docs/DEPLOYMENT.md 准备配置"
  git fetch -q origin --tags
  if [ -z "$v" ]; then
    tag=$(git tag -l 'v*' --sort=-v:refname | head -1)
    [ -n "$tag" ] || die "还没有任何 v* 标签"
  else
    tag=v${v#v}
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "没有标签 $tag"
  fi
  v=${tag#v}

  # Build from a clean checkout of the tag, whatever branch this tree is on.
  # tmp and wt stay global so the EXIT trap can still see them.
  tmp=$(mktemp -d)
  wt=$tmp/meridian
  git worktree add -q --detach "$wt" "$tag"
  trap 'git worktree remove --force "$wt"; rmdir "$tmp"' EXIT

  if grep -q '^MERIDIAN_VERSION=' "$env"; then
    replace "$env" "$(grep '^MERIDIAN_VERSION=' "$env")" "MERIDIAN_VERSION=$v"
  else
    echo "MERIDIAN_VERSION=$v" >>"$env"
  fi

  say "构建并启动 $tag……"
  docker compose --env-file "$env" -f "$wt/deploy/docker-compose.yml" up -d --build

  port=$(sed -n 's/^MERIDIAN_PORT=//p' "$env"); port=${port:-8090}
  base=$(sed -n 's/^MERIDIAN_BASE_PATH=//p' "$env")
  grep -q '^MERIDIAN_BASE_PATH=' "$env" || base=/meridian
  url="http://127.0.0.1:$port$base/healthz"
  for _ in $(seq 30); do
    curl -fsS "$url" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fsS "$url" >/dev/null || die "$url 没有返回 200：docker compose -f deploy/docker-compose.yml logs server"
  say "已部署 $(docker compose --env-file "$env" -f "$wt/deploy/docker-compose.yml" exec -T server /meridian-server version)"
}

case ${1:-} in
  bump) shift; cmd_bump "$@" ;;
  publish) shift; cmd_publish "$@" ;;
  deploy) shift; cmd_deploy "$@" ;;
  *) usage ;;
esac
