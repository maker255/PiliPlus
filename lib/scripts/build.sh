#!/usr/bin/env bash

# 让脚本在命令失败、使用未定义变量或管道失败时立即停止。
set -euo pipefail

# 第一个参数仅用于 Android：Android 版本名会额外附加短提交哈希。
platform="${1:-}"

# Windows Runner 的 Git Bash 可能收到 D:\\... 形式的环境变量；转换成 Bash 可识别的路径。
to_posix_path() {
  case "$1" in
    [A-Za-z]:\\*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$1"
      else
        printf '%s' "$1"
      fi
      ;;
    *) printf '%s' "$1" ;;
  esac
}

# 以仓库根目录作为工作目录，避免从其他目录调用脚本时找不到文件。
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace="$(cd -- "$script_dir/../.." && pwd)"
cd "$workspace"

# 版本号使用 Git 提交总数，保证每次提交都得到递增的 Android versionCode。
version_code="$(git rev-list --count HEAD)"
commit_hash="$(git rev-parse HEAD)"

# 从 pubspec.yaml 读取三段式版本号，例如 2.1.0。
version_name="$(sed -nE 's/^version:[[:space:]]*([0-9]+(\.[0-9]+){2}).*/\1/p' pubspec.yaml | head -n 1)"
if [[ -z "$version_name" ]]; then
  echo "错误：在 pubspec.yaml 中找不到版本号" >&2
  exit 1
fi

# Android 使用带提交哈希的版本名，其他平台使用原始版本名。
if [[ "$(printf '%s' "$platform" | tr '[:upper:]' '[:lower:]')" == "android" ]]; then
  version_name="${version_name}-${commit_hash:0:9}"
fi

# 将动态版本写回 pubspec.yaml；该文件只在构建工作区中修改，不应提交回仓库。
TEMP_PUBSPEC="$(mktemp)"
awk -v version="$version_name" -v code="$version_code" '
  !done && $0 ~ /^[[:space:]]*version:[[:space:]]*[0-9]+(\.[0-9]+){2}/ {
    print "version: " version "+" code
    done = 1
    next
  }
  { print }
' pubspec.yaml > "$TEMP_PUBSPEC"
mv "$TEMP_PUBSPEC" pubspec.yaml

# 将构建元数据传给 Dart；该文件已被 .gitignore 忽略。
build_time="$(date +%s)"
cat > pili_release.json <<EOF
{"pili.name":"$version_name","pili.code":"$version_code","pili.hash":"$commit_hash","pili.time":$build_time}
EOF

# GitHub Actions 通过 GITHUB_ENV 让后续步骤使用 version；本地运行时没有该变量也应成功。
if [[ -n "${GITHUB_ENV:-}" ]]; then
  github_env_file="$(to_posix_path "$GITHUB_ENV")"
  printf 'version=%s+%s\n' "$version_name" "$version_code" >> "$github_env_file"
fi

echo "构建版本：$version_name+$version_code"
echo "提交哈希：$commit_hash"
