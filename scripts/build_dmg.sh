#!/usr/bin/env bash
#
# 打包 HostsEditor 为 DMG：构建 Release，生成 HostsEditor_V_<版本号>.dmg，可选公证。
# 用法:
#   ./scripts/build_dmg.sh [--keychain-profile PROFILE] [--no-notarize]
# 默认使用 --keychain-profile "vanjay_mac_stapler" 进行公证；传入 --no-notarize 则跳过公证。
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="HostsEditor"
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
DMG_OUTPUT_DIR="$BUILD_DIR/dmg"
KEYCHAIN_PROFILE="vanjay_mac_stapler"
DO_NOTARIZE=true
APP_ENTITLEMENTS="$PROJECT_DIR/HostsEditor/HostsEditor-Release.entitlements"
HELPER_ENTITLEMENTS="$PROJECT_DIR/HostsEditorHelper/HostsEditorHelper-Release.entitlements"

generate_dmg_background() {
    local output_path="$1"

    /usr/bin/swift - "$output_path" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("missing output path\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let size = NSSize(width: 620, height: 360)
let rect = NSRect(origin: .zero, size: size)

let image = NSImage(size: size)
image.lockFocus()

let outer = NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24)
NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill()
outer.fill()

let topBand = NSRect(x: 0, y: 258, width: size.width, height: 102)
let bandPath = NSBezierPath(roundedRect: topBand, xRadius: 24, yRadius: 24)
NSColor(calibratedRed: 0.87, green: 0.93, blue: 0.99, alpha: 1).setFill()
bandPath.fill()

let topMask = NSRect(x: 0, y: 258, width: size.width, height: 50)
NSColor(calibratedRed: 0.87, green: 0.93, blue: 0.99, alpha: 1).setFill()
topMask.fill()

func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    text.draw(in: rect, withAttributes: attributes)
}

func drawPanel(_ rect: NSRect) {
    let panel = NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)
    NSColor(calibratedWhite: 1.0, alpha: 0.9).setFill()
    panel.fill()

    NSColor(calibratedRed: 0.80, green: 0.85, blue: 0.92, alpha: 0.9).setStroke()
    panel.lineWidth = 2
    panel.stroke()
}

drawPanel(NSRect(x: 58, y: 72, width: 192, height: 168))
drawPanel(NSRect(x: 370, y: 72, width: 192, height: 168))

let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: 272, y: 156))
arrowPath.line(to: NSPoint(x: 356, y: 156))
arrowPath.lineWidth = 14
arrowPath.lineCapStyle = .round
NSColor(calibratedRed: 0.24, green: 0.53, blue: 0.92, alpha: 1).setStroke()
arrowPath.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 354, y: 178))
head.line(to: NSPoint(x: 392, y: 156))
head.line(to: NSPoint(x: 354, y: 134))
head.close()
NSColor(calibratedRed: 0.24, green: 0.53, blue: 0.92, alpha: 1).setFill()
head.fill()

drawText(
    "Drag HostsEditor to Applications",
    rect: NSRect(x: 60, y: 286, width: 500, height: 34),
    font: NSFont(name: "Avenir Next Demi Bold", size: 26) ?? .systemFont(ofSize: 26, weight: .semibold),
    color: NSColor(calibratedRed: 0.09, green: 0.18, blue: 0.30, alpha: 1)
)

drawText(
    "Install by dragging the app onto the Applications shortcut",
    rect: NSRect(x: 70, y: 250, width: 480, height: 24),
    font: NSFont(name: "Avenir Next Regular", size: 14) ?? .systemFont(ofSize: 14, weight: .regular),
    color: NSColor(calibratedRed: 0.26, green: 0.34, blue: 0.45, alpha: 1)
)

let badge = NSBezierPath(roundedRect: NSRect(x: 230, y: 128, width: 54, height: 54), xRadius: 27, yRadius: 27)
NSColor(calibratedRed: 0.90, green: 0.95, blue: 1.0, alpha: 1).setFill()
badge.fill()

drawText(
    "1",
    rect: NSRect(x: 245, y: 137, width: 24, height: 24),
    font: .systemFont(ofSize: 22, weight: .bold),
    color: NSColor(calibratedRed: 0.24, green: 0.53, blue: 0.92, alpha: 1)
)

let badge2 = NSBezierPath(roundedRect: NSRect(x: 336, y: 128, width: 54, height: 54), xRadius: 27, yRadius: 27)
NSColor(calibratedRed: 0.90, green: 0.95, blue: 1.0, alpha: 1).setFill()
badge2.fill()

drawText(
    "2",
    rect: NSRect(x: 351, y: 137, width: 24, height: 24),
    font: .systemFont(ofSize: 22, weight: .bold),
    color: NSColor(calibratedRed: 0.24, green: 0.53, blue: 0.92, alpha: 1)
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render png\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
SWIFT
}

verify_signature() {
    local target_path="$1"
    local target_name="$2"
    local sign_info

    echo "校验签名: $target_name"
    sign_info="$(codesign -dv --verbose=4 "$target_path" 2>&1)"

    if ! grep -q "Authority=Developer ID Application" <<<"$sign_info"; then
        echo "错误: $target_name 未使用 Developer ID Application 签名" >&2
        echo "$sign_info" >&2
        exit 1
    fi

    if ! grep -q "Timestamp=" <<<"$sign_info"; then
        echo "错误: $target_name 签名缺少 secure timestamp" >&2
        echo "$sign_info" >&2
        exit 1
    fi
}

current_signing_authority() {
    local target_path="$1"
    codesign -dv --verbose=4 "$target_path" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -1
}

resign_macho_file() {
    local target_path="$1"
    local identity="$2"
    /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime "$target_path"
}

resign_for_notarization() {
    local identity="$1"
    local frameworks_dir="$APP_PATH/Contents/Frameworks"

    echo "重新签名发布产物并补充 secure timestamp..."

    if [[ -d "$frameworks_dir" ]]; then
        while IFS= read -r -d '' file_path; do
            if file "$file_path" | grep -q "Mach-O"; then
                resign_macho_file "$file_path" "$identity"
            fi
        done < <(find "$frameworks_dir" -type f -print0)
    fi

    /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime \
        --entitlements "$HELPER_ENTITLEMENTS" \
        "$HELPER_PATH"

    /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime \
        --entitlements "$APP_ENTITLEMENTS" \
        "$APP_PATH"
}

create_pretty_dmg() {
    local app_path="$1"
    local dmg_path="$2"
    local volume_name="$3"
    local work_dir="$BUILD_DIR/dmg-tmp"
    local staging_dir="$work_dir/staging"
    local background_dir="$staging_dir/.background"
    local background_path="$background_dir/installer-background.png"
    local rw_dmg_path="$work_dir/${volume_name}.temp.dmg"
    local app_name
    local device
    local attach_output
    local mounted_volume_path
    local mounted_volume_name

    app_name="$(basename "$app_path")"

    rm -rf "$work_dir"
    mkdir -p "$staging_dir" "$background_dir"
    cp -R "$app_path" "$staging_dir/"
    generate_dmg_background "$background_path"
    chflags hidden "$background_dir" 2>/dev/null || true

    hdiutil create -volname "$volume_name" \
        -srcfolder "$staging_dir" \
        -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" \
        -ov -format UDRW \
        "$rw_dmg_path"

    attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "$rw_dmg_path")"
    device="$(printf '%s\n' "$attach_output" | awk -F '\t' '/\/Volumes\// {print $1; exit}')"
    mounted_volume_path="$(printf '%s\n' "$attach_output" | awk -F '\t' '/\/Volumes\// {print $NF; exit}')"
    mounted_volume_name="$(basename "$mounted_volume_path")"

    if [[ -z "$device" || -z "$mounted_volume_name" ]]; then
        echo "错误: 无法挂载临时 DMG" >&2
        echo "$attach_output" >&2
        exit 1
    fi

    osascript <<EOF
tell application "Finder"
    make new alias file at POSIX file "$mounted_volume_path" to POSIX file "/Applications" with properties {name:"Applications"}
end tell
EOF

    # 用 Finder 写入 .DS_Store，控制窗口尺寸、背景图和图标位置。
    osascript <<EOF
tell application "Finder"
    tell disk "$mounted_volume_name"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {220, 120, 840, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 104
        set text size of viewOptions to 14
        set background picture of viewOptions to file ".background:installer-background.png"
        set position of every item of container window to {760, 40}
        set position of item "$app_name" of container window to {154, 188}
        set position of item "Applications" of container window to {466, 188}
        close
        open
        update without registering applications
        delay 1
        set bounds of container window to {220, 120, 830, 510}
        delay 1
        set bounds of container window to {220, 120, 840, 520}
        delay 2
    end tell
end tell
EOF

    if [[ -e "$mounted_volume_path/.fseventsd" ]]; then
        chflags hidden "$mounted_volume_path/.fseventsd" 2>/dev/null || true
    fi

    sync
    sleep 1
    hdiutil detach "$mounted_volume_path" || hdiutil detach "$device" -force
    hdiutil convert "$rw_dmg_path" -format UDZO -imagekey zlib-level=9 -o "$dmg_path"
    rm -rf "$work_dir"
}

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

# 构建（arm64 + x86_64，Release 需使用 Developer ID Application 签名）
echo "构建 $SCHEME (Release, arm64 + x86_64)..."
xcodebuild -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    clean build

if [[ ! -d "$APP_PATH" ]]; then
    echo "错误: 未找到构建产物 $APP_PATH" >&2
    exit 1
fi

HELPER_PATH="$APP_PATH/Contents/Library/LaunchServices/cn.vanjay.HostsEditor.Helper"
SIGNING_AUTHORITY="$(current_signing_authority "$APP_PATH")"
if [[ -z "$SIGNING_AUTHORITY" ]]; then
    echo "错误: 未能从构建产物识别 Developer ID Application 签名身份" >&2
    exit 1
fi

resign_for_notarization "$SIGNING_AUTHORITY"
verify_signature "$APP_PATH" "HostsEditor.app"
verify_signature "$HELPER_PATH" "cn.vanjay.HostsEditor.Helper"

# 准备 DMG 输出目录
mkdir -p "$DMG_OUTPUT_DIR"
DMG_PATH="$DMG_OUTPUT_DIR/$DMG_NAME"
VOLUME_NAME="HostsEditor V$VERSION"

# 若已存在同名 DMG 先删除，避免 hdiutil 报错
rm -f "$DMG_PATH"

# 创建 DMG（包含 Applications 快捷方式和预设窗口布局）
echo "生成 DMG: $DMG_PATH"
create_pretty_dmg "$APP_PATH" "$DMG_PATH" "$VOLUME_NAME"

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
