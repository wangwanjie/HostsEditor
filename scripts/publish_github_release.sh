#!/usr/bin/env bash
#
# 将 DMG 上传到 GitHub Releases。
# 默认上传 build/dmg/ 下最新的 HostsEditor_V_*.dmg，
# 默认优先从 git remote origin_github 推断 GitHub 仓库，再回退到其他 github.com remote。
#
# 用法:
#   ./scripts/publish_github_release.sh [--dmg PATH] [--repo OWNER/REPO] [--tag TAG]
#                                       [--title TITLE] [--notes TEXT | --notes-file FILE | --generate-notes]
#                                       [--draft] [--prerelease]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_DMG_DIR="$PROJECT_DIR/build/dmg"
PBXPROJ="$PROJECT_DIR/HostsEditor.xcodeproj/project.pbxproj"
INFO_PLIST="$PROJECT_DIR/HostsEditor/Info.plist"

DMG_PATH=""
REPO=""
TAG=""
TITLE=""
NOTES=""
NOTES_FILE=""
GENERATE_NOTES=false
DRAFT=false
PRERELEASE=false

usage() {
    cat <<'EOF'
用法:
  ./scripts/publish_github_release.sh [--dmg PATH] [--repo OWNER/REPO] [--tag TAG]
                                     [--title TITLE] [--notes TEXT | --notes-file FILE | --generate-notes]
                                     [--draft] [--prerelease]

选项:
  --dmg PATH          指定要上传的 DMG 路径。默认选择 build/dmg/ 下最新的 HostsEditor_V_*.dmg
  --repo OWNER/REPO   指定 GitHub 仓库，例如 wangwanjie/HostsEditor
  --tag TAG           指定 release tag，默认根据版本号生成，例如 v1.0
  --title TITLE       指定 release 标题，默认格式为 HostsEditor v<版本号>
  --notes TEXT        指定 release 说明文本
  --notes-file FILE   从文件读取 release 说明
  --generate-notes    让 GitHub 自动生成 release notes
  --draft             创建草稿 release
  --prerelease        创建预发布 release
  -h, --help          显示帮助

前置条件:
  1. 已安装 GitHub CLI: https://cli.github.com/
  2. 已完成登录: gh auth login
  3. 当前仓库存在指向 github.com 的 remote，或显式传入 --repo

示例:
  ./scripts/build_dmg.sh --no-notarize
  ./scripts/publish_github_release.sh

  ./scripts/publish_github_release.sh \
    --repo wangwanjie/HostsEditor \
    --tag v1.0 \
    --title "HostsEditor v1.0" \
    --generate-notes
EOF
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "错误: 未找到命令 $cmd" >&2
        exit 1
    fi
}

read_plist_string() {
    local key="$1"
    /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" 2>/dev/null || true
}

resolve_path() {
    local input_path="$1"
    local candidate="$input_path"

    if [[ ! "$candidate" = /* ]]; then
        if [[ -e "$candidate" ]]; then
            :
        elif [[ -e "$PROJECT_DIR/$candidate" ]]; then
            candidate="$PROJECT_DIR/$candidate"
        fi
    fi

    if [[ ! -e "$candidate" ]]; then
        echo ""
        return 0
    fi

    (
        cd "$(dirname "$candidate")"
        printf '%s/%s\n' "$(pwd)" "$(basename "$candidate")"
    )
}

extract_github_repo_from_url() {
    local remote_url="$1"

    if [[ "$remote_url" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi

    if [[ "$remote_url" =~ ^git@github\.com:([^/]+)/([^/]+)(\.git)?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi

    if [[ "$remote_url" =~ ^ssh://git@github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi

    return 1
}

detect_repo() {
    local remote_url
    local repo_name

    if remote_url="$(read_plist_string "HostsEditorGitHubURL")"; then
        if repo_name="$(extract_github_repo_from_url "$remote_url" 2>/dev/null)"; then
            printf '%s\n' "$repo_name"
            return 0
        fi
    fi

    if remote_url="$(git remote get-url origin_github 2>/dev/null)"; then
        if repo_name="$(extract_github_repo_from_url "$remote_url" 2>/dev/null)"; then
            printf '%s\n' "$repo_name"
            return 0
        fi
    fi

    while IFS=$'\t' read -r _remote_name candidate_url; do
        if repo_name="$(extract_github_repo_from_url "$candidate_url" 2>/dev/null)"; then
            printf '%s\n' "$repo_name"
            return 0
        fi
    done < <(git remote -v | awk '$3=="(push)" {print $1 "\t" $2}' | awk '!seen[$1]++')

    return 1
}

find_latest_dmg() {
    local latest_path=""
    local latest_mtime=0
    local file_path
    local file_mtime

    shopt -s nullglob
    for file_path in "$DEFAULT_DMG_DIR"/HostsEditor_V_*.dmg; do
        [[ -f "$file_path" ]] || continue
        file_mtime="$(stat -f '%m' "$file_path")"
        if [[ -z "$latest_path" || "$file_mtime" -gt "$latest_mtime" ]]; then
            latest_path="$file_path"
            latest_mtime="$file_mtime"
        fi
    done
    shopt -u nullglob

    printf '%s\n' "$latest_path"
}

infer_version_from_dmg() {
    local dmg_name
    dmg_name="$(basename "$1")"

    if [[ "$dmg_name" =~ ^HostsEditor_V_(.+)\.dmg$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

read_marketing_version() {
    if [[ -f "$PBXPROJ" ]]; then
        grep -m1 "MARKETING_VERSION" "$PBXPROJ" | sed 's/.*MARKETING_VERSION = \([^;]*\);/\1/' | tr -d ' '
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)
            if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
                echo "错误: --dmg 需要指定路径" >&2
                exit 1
            fi
            DMG_PATH="$2"
            shift 2
            ;;
        --repo)
            if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
                echo "错误: --repo 需要指定 OWNER/REPO" >&2
                exit 1
            fi
            REPO="$2"
            shift 2
            ;;
        --tag)
            if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
                echo "错误: --tag 需要指定 tag" >&2
                exit 1
            fi
            TAG="$2"
            shift 2
            ;;
        --title)
            if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
                echo "错误: --title 需要指定标题" >&2
                exit 1
            fi
            TITLE="$2"
            shift 2
            ;;
        --notes)
            if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
                echo "错误: --notes 需要指定文本" >&2
                exit 1
            fi
            NOTES="$2"
            shift 2
            ;;
        --notes-file)
            if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
                echo "错误: --notes-file 需要指定文件路径" >&2
                exit 1
            fi
            NOTES_FILE="$2"
            shift 2
            ;;
        --generate-notes)
            GENERATE_NOTES=true
            shift
            ;;
        --draft)
            DRAFT=true
            shift
            ;;
        --prerelease)
            PRERELEASE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -n "$NOTES" && -n "$NOTES_FILE" ]]; then
    echo "错误: --notes 和 --notes-file 只能二选一" >&2
    exit 1
fi

if [[ "$GENERATE_NOTES" == true && ( -n "$NOTES" || -n "$NOTES_FILE" ) ]]; then
    echo "错误: --generate-notes 不能与 --notes 或 --notes-file 同时使用" >&2
    exit 1
fi

require_command git
require_command gh

if ! gh auth status >/dev/null 2>&1; then
    echo "错误: GitHub CLI 尚未登录，请先执行 gh auth login" >&2
    exit 1
fi

if [[ -n "$DMG_PATH" ]]; then
    DMG_PATH="$(resolve_path "$DMG_PATH")"
else
    DMG_PATH="$(find_latest_dmg)"
fi

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
    echo "错误: 未找到可上传的 DMG，请先执行 ./scripts/build_dmg.sh 或通过 --dmg 指定文件" >&2
    exit 1
fi

if [[ -n "$NOTES_FILE" ]]; then
    NOTES_FILE="$(resolve_path "$NOTES_FILE")"
    if [[ -z "$NOTES_FILE" || ! -f "$NOTES_FILE" ]]; then
        echo "错误: 未找到 notes 文件" >&2
        exit 1
    fi
fi

if [[ -z "$REPO" ]]; then
    if ! REPO="$(detect_repo)"; then
        echo "错误: 无法从 git remote 推断 GitHub 仓库，请通过 --repo OWNER/REPO 指定" >&2
        exit 1
    fi
fi

VERSION="$(infer_version_from_dmg "$DMG_PATH" || true)"
if [[ -z "$VERSION" ]]; then
    VERSION="$(read_marketing_version)"
fi
if [[ -z "$VERSION" ]]; then
    echo "错误: 无法推断版本号，请通过 --tag 和 --title 显式指定发布信息" >&2
    exit 1
fi

if [[ -z "$TAG" ]]; then
    TAG="v$VERSION"
fi

if [[ -z "$TITLE" ]]; then
    TITLE="HostsEditor v$VERSION"
fi

echo "仓库: $REPO"
echo "Tag: $TAG"
echo "标题: $TITLE"
echo "DMG: $DMG_PATH"

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    echo "Release 已存在，上传并覆盖同名资源..."
    gh release upload "$TAG" "$DMG_PATH" -R "$REPO" --clobber
else
    echo "Release 不存在，正在创建..."
    create_args=(release create "$TAG" "$DMG_PATH" -R "$REPO" --title "$TITLE")

    if [[ "$GENERATE_NOTES" == true ]]; then
        create_args+=(--generate-notes)
    elif [[ -n "$NOTES_FILE" ]]; then
        create_args+=(--notes-file "$NOTES_FILE")
    else
        create_args+=(--notes "${NOTES:-Release $TAG}")
    fi

    if [[ "$DRAFT" == true ]]; then
        create_args+=(--draft)
    fi

    if [[ "$PRERELEASE" == true ]]; then
        create_args+=(--prerelease)
    fi

    gh "${create_args[@]}"
fi

echo "完成: https://github.com/$REPO/releases/tag/$TAG"

APPCAST_NOTES="$(gh release view "$TAG" -R "$REPO" --json body --jq '.body // ""' 2>/dev/null || true)"
APPCAST_ARGS=(--repo "$REPO" --archive "$DMG_PATH")
if [[ -n "$APPCAST_NOTES" ]]; then
    APPCAST_ARGS+=(--notes "$APPCAST_NOTES")
fi

"$PROJECT_DIR/scripts/generate_appcast.sh" "${APPCAST_ARGS[@]}"

echo "appcast 已更新: $PROJECT_DIR/appcast.xml"
echo "请将 appcast.xml 一并提交并推送到 GitHub 默认分支。"
