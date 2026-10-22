#!/usr/bin/env bash
#
# 按架构分别打包 HostsEditor：每个架构单独归档 Release，生成 HostsEditor_V_<版本号>_<arch>.dmg，可选公证。
# 各架构包的 SUFeedURL 指向对应的 appcast-<arch>.xml，只会收到同架构的更新。
#
# 用法:
#   ./scripts/build_dmg.sh [--arch arm64|x86_64]... [--keychain-profile PROFILE] [--no-notarize] [--skip-archive]
# 默认同时构建 arm64 与 x86_64；--arch 可重复传入，只构建指定架构。
# 默认使用 --keychain-profile "vanjay_mac_stapler" 进行公证；传入 --no-notarize 则跳过公证。
# --skip-archive 复用 build/HostsEditor-<arch>.xcarchive，只重新签名、打包和公证。
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="HostsEditor"
WORKSPACE="HostsEditor.xcworkspace"
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
DMG_OUTPUT_DIR="$BUILD_DIR/dmg"
KEYCHAIN_PROFILE="vanjay_mac_stapler"
DO_NOTARIZE=true
DO_ARCHIVE=true
ARCHS_TO_BUILD=()
SUPPORTED_ARCHS=(arm64 x86_64)
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
        static let subtitleText = "Install the hosts profile switcher by dragging it onto the Applications shortcut"
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
    local app_path="$2"
    local helper_path="$app_path/Contents/MacOS/HostsEditorHelper"
    local frameworks_dir="$app_path/Contents/Frameworks"

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
            "$helper_path"
    else
        /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime \
            "$helper_path"
    fi

    /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime \
        --entitlements "$APP_ENTITLEMENTS" \
        "$app_path"

    # 整体严格校验一遍，提前发现嵌套代码签名问题，避免等到公证阶段才失败
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
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
        --arch)
            if [[ -z "${2:-}" || "$2" == --* ]]; then
                echo "错误: --arch 需要指定 arm64 或 x86_64" >&2
                exit 1
            fi
            ARCHS_TO_BUILD+=("$2")
            shift 2
            ;;
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
        --skip-archive)
            DO_ARCHIVE=false
            shift
            ;;
        -h|--help)
            echo "用法: $0 [--arch arm64|x86_64]... [--keychain-profile PROFILE] [--no-notarize] [--skip-archive]"
            echo "  默认同时构建 arm64 与 x86_64"
            echo "  默认公证使用: --keychain-profile \"vanjay_mac_stapler\""
            echo "  --no-notarize  跳过公证"
            echo "  --skip-archive 复用已有归档，只重新签名与打包"
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            exit 1
            ;;
    esac
done

if [[ ${#ARCHS_TO_BUILD[@]} -eq 0 ]]; then
    ARCHS_TO_BUILD=("${SUPPORTED_ARCHS[@]}")
fi
for arch in "${ARCHS_TO_BUILD[@]}"; do
    if [[ " ${SUPPORTED_ARCHS[*]} " != *" $arch "* ]]; then
        echo "错误: 不支持的架构 $arch（可选: ${SUPPORTED_ARCHS[*]}）" >&2
        exit 1
    fi
done

cd "$PROJECT_DIR"

# 从工程文件读取版本号（不依赖 xcodebuild -showBuildSettings）
echo "读取版本号..."
VERSION=""
PBXPROJ="$PROJECT_DIR/HostsEditor.xcodeproj/project.pbxproj"
if [[ -f "$PBXPROJ" ]]; then
    VERSION=$(grep -m1 "MARKETING_VERSION" "$PBXPROJ" | sed 's/.*MARKETING_VERSION = \([^;]*\);/\1/' | tr -d ' ')
fi
if [[ -z "$VERSION" ]]; then
    echo "错误: 无法从 project.pbxproj 读取 MARKETING_VERSION" >&2
    exit 1
fi
echo "版本号: $VERSION，架构: ${ARCHS_TO_BUILD[*]}"

# 第一个架构确定签名身份，后续架构复用，保证各包签名一致
SIGNING_AUTHORITY=""
BUILT_DMGS=()

notarize_dmg() {
    local dmg_path="$1"
    local notary_output
    local notary_id

    echo "提交公证 (keychain-profile: $KEYCHAIN_PROFILE)..."
    notary_output=$(xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait 2>&1) || true
    echo "$notary_output"
    if echo "$notary_output" | grep -q "status: Accepted"; then
        echo "公证成功，正在钉合 (staple)..."
        xcrun stapler staple "$dmg_path"
        echo "公证并钉合完成。"
    else
        echo "公证未通过 (status 非 Accepted)。" >&2
        notary_id=$(echo "$notary_output" | sed -n 's/.*id:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
        if [[ -n "$notary_id" ]]; then
            echo "查看失败原因: xcrun notarytool log $notary_id --keychain-profile \"$KEYCHAIN_PROFILE\"" >&2
        fi
        exit 1
    fi
}

build_arch() {
    local arch="$1"
    local archive_path="$BUILD_DIR/HostsEditor-$arch.xcarchive"
    local app_path="$archive_path/Products/Applications/HostsEditor.app"
    local helper_path="$app_path/Contents/MacOS/HostsEditorHelper"
    local binary_archs
    local helper_archs
    local feed_url

    echo "========== $arch =========="
    if [[ "$DO_ARCHIVE" == true ]]; then
        # 使用 archive，避免 scheme 的 BuildAction 在多 target 场景下误构建 Debug runnable target。
        # HOSTSEDITOR_APPCAST_NAME 决定 Info.plist 中的 SUFeedURL，让各架构只收到同架构的更新。
        echo "归档 $SCHEME (Release, $arch)..."
        rm -rf "$archive_path"
        xcodebuild -workspace "$WORKSPACE" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -derivedDataPath "$DERIVED_DATA" \
            -archivePath "$archive_path" \
            -destination "generic/platform=macOS" \
            ARCHS="$arch" \
            ONLY_ACTIVE_ARCH=NO \
            HOSTSEDITOR_APPCAST_NAME="appcast-$arch.xml" \
            clean archive
    fi

    if [[ ! -d "$app_path" ]]; then
        echo "错误: 未找到构建产物 $app_path" >&2
        exit 1
    fi

    # 确认主程序与 Helper 都只包含目标架构，且 feed 地址正确
    binary_archs="$(lipo -archs "$app_path/Contents/MacOS/HostsEditor")"
    helper_archs="$(lipo -archs "$helper_path")"
    if [[ "$binary_archs" != "$arch" || "$helper_archs" != "$arch" ]]; then
        echo "错误: 主程序架构为 '$binary_archs'，Helper 架构为 '$helper_archs'，预期均为 '$arch'" >&2
        exit 1
    fi
    feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app_path/Contents/Info.plist")"
    if [[ "$feed_url" != *"/appcast-$arch.xml" ]]; then
        echo "错误: SUFeedURL 为 '$feed_url'，预期指向 appcast-$arch.xml" >&2
        exit 1
    fi
    echo "SUFeedURL: $feed_url"

    if [[ -z "$SIGNING_AUTHORITY" ]]; then
        SIGNING_AUTHORITY="$(current_signing_authority "$app_path")"
    fi
    if [[ -z "$SIGNING_AUTHORITY" ]]; then
        echo "错误: 未能从构建产物识别 Developer ID Application 签名身份" >&2
        exit 1
    fi

    resign_for_notarization "$SIGNING_AUTHORITY" "$app_path"
    verify_signature "$app_path" "HostsEditor.app ($arch)"
    verify_signature "$helper_path" "HostsEditorHelper ($arch)"

    mkdir -p "$DMG_OUTPUT_DIR"
    local dmg_path="$DMG_OUTPUT_DIR/HostsEditor_V_${VERSION}_${arch}.dmg"
    local volume_name="HostsEditor V$VERSION"

    # 若已存在同名 DMG 先删除，避免 hdiutil 报错
    rm -f "$dmg_path"

    # 创建 DMG（包含 Applications 快捷方式和预设窗口布局）
    echo "生成 DMG: $dmg_path"
    create_pretty_dmg "$app_path" "$dmg_path" "$volume_name"
    echo "DMG 已生成: $dmg_path"

    if [[ "$DO_NOTARIZE" == true ]]; then
        notarize_dmg "$dmg_path"
    else
        echo "已跳过公证 (--no-notarize)。"
    fi

    BUILT_DMGS+=("$dmg_path")
}

for arch in "${ARCHS_TO_BUILD[@]}"; do
    build_arch "$arch"
done

echo "完成。产物:"
printf '  %s\n' "${BUILT_DMGS[@]}"
