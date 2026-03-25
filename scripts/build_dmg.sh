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
WORKSPACE="HostsEditor.xcworkspace"
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
ARCHIVE_PATH="$BUILD_DIR/HostsEditor.xcarchive"
DMG_OUTPUT_DIR="$BUILD_DIR/dmg"
KEYCHAIN_PROFILE="vanjay_mac_stapler"
DO_NOTARIZE=true
APP_ENTITLEMENTS="$PROJECT_DIR/HostsEditor/HostsEditor-Release.entitlements"
HELPER_ENTITLEMENTS="$PROJECT_DIR/HostsEditorHelper/HostsEditorHelper-Release.entitlements"

generate_dmg_background() {
    local output_path="$1"

    /usr/bin/swift - "$output_path" <<'SWIFT'
import Cocoa
import Foundation

// 获取输出路径
guard CommandLine.arguments.count >= 2 else {
    fputs("Error: Missing output path\n", stderr)
    exit(1)
}
let outputPath = CommandLine.arguments[1]

// MARK: - BackgroundView Definition
class BackgroundView: NSView {
    private enum Constants {
        static let imageWidth: CGFloat = 620
        static let imageHeight: CGFloat = 360
        static let backgroundColor = NSColor(srgbRed: 0.95, green: 0.97, blue: 0.98, alpha: 1)
        static let topGradientColor = NSColor(srgbRed: 0.80, green: 0.90, blue: 0.95, alpha: 1)
        static let accentColor = NSColor(calibratedRed: 0.11, green: 0.43, blue: 0.63, alpha: 1)
        static let textColor = NSColor(srgbRed: 0.10, green: 0.17, blue: 0.24, alpha: 1)
        static let subtitleColor = NSColor(srgbRed: 0.28, green: 0.35, blue: 0.42, alpha: 1)
        static let panelFillColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.94)
        static let panelStrokeColor = NSColor(srgbRed: 0.73, green: 0.83, blue: 0.90, alpha: 1)
        static let cornerRadius: CGFloat = 24
        static let panelCornerRadius: CGFloat = 26
        static let panelStrokeWidth: CGFloat = 2
        static let titleFont = NSFont(name: "Avenir Next Demi Bold", size: 26) ?? .systemFont(ofSize: 26, weight: .semibold)
        static let subtitleFont = NSFont(name: "Avenir Next Regular", size: 14) ?? .systemFont(ofSize: 14)
        static let titleText = "Drag HostsEditor to Applications"
        static let subtitleText = "Install the native macOS inspector by dragging it onto the Applications shortcut"
    }

    override func draw(_ dirtyRect: NSRect) {
        // 背景
        let path = NSBezierPath(roundedRect: bounds, xRadius: Constants.cornerRadius, yRadius: Constants.cornerRadius)
        Constants.backgroundColor.setFill()
        path.fill()

        // 渐变头 (y=0 在底部)
        let headerRect = NSRect(x: 0, y: 250, width: bounds.width, height: 110)
        let gradient = NSGradient(starting: Constants.topGradientColor, ending: Constants.backgroundColor)!
        gradient.draw(in: headerRect, angle: -90)

        // 文字
        drawText(Constants.titleText, font: Constants.titleFont, color: Constants.textColor, in: NSRect(x: 60, y: 286, width: 500, height: 34))
        drawText(Constants.subtitleText, font: Constants.subtitleFont, color: Constants.subtitleColor, in: NSRect(x: 70, y: 242, width: 480, height: 24))

        // 面板
        drawPanel(NSRect(x: 58, y: 72, width: 192, height: 168))
        drawPanel(NSRect(x: 370, y: 72, width: 192, height: 168))

        // 箭头
        let arrowBody = NSBezierPath()
        arrowBody.move(to: NSPoint(x: 254, y: 156))
        arrowBody.line(to: NSPoint(x: 338, y: 156))
        Constants.accentColor.setStroke()
        arrowBody.lineWidth = 14
        arrowBody.stroke()

        let arrowHead = NSBezierPath()
        arrowHead.move(to: NSPoint(x: 326, y: 178))
        arrowHead.line(to: NSPoint(x: 364, y: 156))
        arrowHead.line(to: NSPoint(x: 326, y: 134))
        arrowHead.close()
        Constants.accentColor.setFill()
        arrowHead.fill()
    }

    private func drawPanel(_ rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: Constants.panelCornerRadius, yRadius: Constants.panelCornerRadius)
        Constants.panelFillColor.setFill()
        path.fill()
        Constants.panelStrokeColor.setStroke()
        path.lineWidth = Constants.panelStrokeWidth
        path.stroke()
    }

    private func drawText(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}

// MARK: - Execution
let width = 620
let height = 360
let frame = NSRect(x: 0, y: 0, width: width, height: height)
let view = BackgroundView(frame: frame)

// 关键步骤：将 View 内容捕获为 Bitmap
guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: frame) else {
    fputs("Error: Could not create bitmap rep\n", stderr)
    exit(1)
}

// 强制进行绘制到 bitmap
view.cacheDisplay(in: frame, to: bitmapRep)

// 转换为 PNG 数据
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fputs("Error: Could not generate PNG data\n", stderr)
    exit(1)
}

// 写入文件
do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
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

    if [[ -f "$HELPER_ENTITLEMENTS" ]]; then
        /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime \
            --entitlements "$HELPER_ENTITLEMENTS" \
            "$HELPER_PATH"
    else
        /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime \
            "$HELPER_PATH"
    fi

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
    ln -s /Applications "$staging_dir/Applications"
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
        set icon size of viewOptions to 96
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:installer-background.png"
        set position of every item of container window to {760, 40}
        set position of item "$app_name" of container window to {154, 160}
        set position of item "Applications" of container window to {466, 160}
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
APP_PATH="$ARCHIVE_PATH/Products/Applications/HostsEditor.app"

# 使用 archive，避免 scheme 的 BuildAction 在多 target 场景下误构建 Debug runnable target。
# 归档（arm64 + x86_64，Release 需使用 Developer ID Application 签名）
echo "归档 $SCHEME (Release, arm64 + x86_64)..."
xcodebuild -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    clean archive

if [[ ! -d "$APP_PATH" ]]; then
    echo "错误: 未找到构建产物 $APP_PATH" >&2
    exit 1
fi

HELPER_PATH="$APP_PATH/Contents/MacOS/HostsEditorHelper"
SIGNING_AUTHORITY="$(current_signing_authority "$APP_PATH")"
if [[ -z "$SIGNING_AUTHORITY" ]]; then
    echo "错误: 未能从构建产物识别 Developer ID Application 签名身份" >&2
    exit 1
fi

resign_for_notarization "$SIGNING_AUTHORITY"
verify_signature "$APP_PATH" "HostsEditor.app"
verify_signature "$HELPER_PATH" "HostsEditorHelper"

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
