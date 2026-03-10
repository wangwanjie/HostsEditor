#!/usr/bin/env bash
#
# 打包 HostsEditor 为 DMG：构建 Release，生成 HostsEditor_V_<版本号>.dmg，可选公证。
# 用法:
#   ./scripts/build_dmg.sh [--keychain-profile PROFILE] [--no-notarize]
# 默认使用 --keychain-profile "vanjay_mac_stapler" 进行公证；传入 --no-notarize 则跳过公证。
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="HostsEditor"
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
DMG_OUTPUT_DIR="$BUILD_DIR/dmg"
KEYCHAIN_PROFILE="vanjay_mac_stapler"
DO_NOTARIZE=true

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --keychain-profile)
            if [[ -z "${2:-}" || "$2" == --* ]]; then
                echo "错误: --keychain-profile 需要指定 profile 名称" >&2
                exit 1
            fi
            KEYCHAIN_PROFILE="$2"
            shift 2
            ;;
        --no-notarize)
            DO_NOTARIZE=false
            shift
            ;;
        -h|--help)
            echo "用法: $0 [--keychain-profile PROFILE] [--no-notarize]"
            echo "  默认公证使用: --keychain-profile \"vanjay_mac_stapler\""
            echo "  --no-notarize  跳过公证"
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

# 从工程文件读取版本号（不依赖 xcodebuild -showBuildSettings）
echo "读取版本号..."
PBXPROJ="$PROJECT_DIR/HostsEditor.xcodeproj/project.pbxproj"
if [[ -f "$PBXPROJ" ]]; then
    VERSION=$(grep -m1 "MARKETING_VERSION" "$PBXPROJ" | sed 's/.*MARKETING_VERSION = \([^;]*\);/\1/' | tr -d ' ')
fi
if [[ -z "$VERSION" ]]; then
    echo "错误: 无法从 project.pbxproj 读取 MARKETING_VERSION" >&2
    exit 1
fi
echo "版本号: $VERSION"

DMG_NAME="HostsEditor_V_${VERSION}.dmg"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/HostsEditor.app"

# 构建（arm64 + x86_64，通用 Mac；Release 在工程内已配置为 Manual + Developer ID）
echo "构建 $SCHEME (Release, arm64 + x86_64)..."
xcodebuild -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    clean build

if [[ ! -d "$APP_PATH" ]]; then
    echo "错误: 未找到构建产物 $APP_PATH" >&2
    exit 1
fi

# 准备 DMG 输出目录
mkdir -p "$DMG_OUTPUT_DIR"
DMG_PATH="$DMG_OUTPUT_DIR/$DMG_NAME"
VOLUME_NAME="HostsEditor V$VERSION"

# 若已存在同名 DMG 先删除，避免 hdiutil 报错
rm -f "$DMG_PATH"

# 创建 DMG（只读、压缩）
echo "生成 DMG: $DMG_PATH"
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_PATH"

echo "DMG 已生成: $DMG_PATH"

# 公证（可选）
if [[ "$DO_NOTARIZE" == true ]]; then
    echo "提交公证 (keychain-profile: $KEYCHAIN_PROFILE)..."
    NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait 2>&1) || true
    echo "$NOTARY_OUTPUT"
    if echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
        echo "公证成功，正在钉合 (staple)..."
        xcrun stapler staple "$DMG_PATH"
        echo "公证并钉合完成。"
    else
        echo "公证未通过 (status 非 Accepted)。" >&2
        if echo "$NOTARY_OUTPUT" | grep -q "id:"; then
            NOTARY_ID=$(echo "$NOTARY_OUTPUT" | sed -n 's/.*id:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
            [[ -n "$NOTARY_ID" ]] && echo "查看失败原因: xcrun notarytool log $NOTARY_ID --keychain-profile \"$KEYCHAIN_PROFILE\"" >&2
        fi
        exit 1
    fi
else
    echo "已跳过公证 (--no-notarize)。"
fi

echo "完成。产物: $DMG_PATH"
