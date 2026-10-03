#!/bin/bash
# NoType 编译并打包为标准 .app（macOS + Command Line Tools，无需完整 Xcode / SPM）
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
CACHE="$HERE/.module-cache"
APP="$HERE/NoType.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

# 干净地重建 .app（仅本任务自己的构建产物）
rm -rf "$APP"
mkdir -p "$MACOS" "$RES" "$CACHE"

# 1) 生成 App 图标（源图可能是 jpeg，先转透明圆角 PNG，再用 Python 组装 .icns）
ICON_SRC="$HERE/assets/appicon.png"
if [ -f "$ICON_SRC" ]; then
    TOOL_BIN="$HERE/.tools/round_icon"
    mkdir -p "$(dirname "$TOOL_BIN")"
    swiftc -sdk "$SDK" -module-cache-path "$CACHE" -O -o "$TOOL_BIN" "$HERE/scripts/round_icon.swift" >/dev/null 2>&1 || true
    ROUNDED="$HERE/assets/appicon_rounded.png"
    "$TOOL_BIN" "$ICON_SRC" "$ROUNDED" 1024

    P512="$HERE/assets/appicon_512.png"
    P128="$HERE/assets/appicon_128.png"
    sips -z 512 512 "$ROUNDED" --out "$P512" >/dev/null 2>&1
    sips -z 128 128 "$ROUNDED" --out "$P128" >/dev/null 2>&1

    python3 "$HERE/scripts/make_icns.py" "$RES/AppIcon.icns" "$P128" "$P512" "$ROUNDED"
    echo "✅ 图标已生成"
fi

# 2) 编译可执行文件
swiftc -sdk "$SDK" \
       -module-cache-path "$CACHE" \
       -O \
       -o "$MACOS/NoType" \
       "$HERE/Sources/Theme.swift" \
       "$HERE/Sources/PromptStore.swift" \
       "$HERE/Sources/ShortcutRecorder.swift" \
       "$HERE/Sources/AppModel.swift" \
       "$HERE/Sources/HomeView.swift" \
       "$HERE/Sources/HistoryView.swift" \
       "$HERE/Sources/SettingsView.swift" \
       "$HERE/Sources/RootView.swift" \
       "$HERE/Sources/VoiceBarView.swift" \
       "$HERE/Sources/SpeechService.swift" \
       "$HERE/Sources/LLMService.swift" \
       "$HERE/Sources/AIEngineManager.swift" \
       "$HERE/Sources/ASREngineManager.swift" \
       "$HERE/Sources/ASRService.swift" \
       "$HERE/Sources/VolcengineStreamASR.swift" \
       "$HERE/Sources/MicrophoneManager.swift" \
       "$HERE/Sources/Log.swift" \
       "$HERE/Sources/TextInjector.swift" \
       "$HERE/Sources/HotKeyManager.swift" \
       "$HERE/Sources/main.swift"

# 3) 写入 bundle Info.plist
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

# 4) 签名：优先用固定的自签名证书（跨编译身份稳定，辅助功能授权不会失效），
#    证书不可用（未信任/无私钥/后台沙箱）时回退 ad-hoc。
SIGN_IDENTITY=""
if security find-identity -v -p codesigning 2>/dev/null | grep -q '"NoType Dev"'; then
    SIGN_IDENTITY="NoType Dev"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    if codesign --force --sign "$SIGN_IDENTITY" "$APP" 2>/dev/null; then
        CHAINS=$(codesign -dvvv "$APP" 2>&1 | grep -c 'Authority=' || true)
        if [ "$CHAINS" -ge 1 ]; then
            echo "✅ 已用固定证书签名: NoType Dev"
        else
            echo "⚠️ 证书签名未生效，回退 ad-hoc"
            codesign --force --sign - "$APP"
        fi
    else
        echo "⚠️ 证书签名失败，回退 ad-hoc"
        codesign --force --sign - "$APP"
    fi
else
    codesign --force --sign - "$APP"
    echo "⚠️ 未找到受信任的 NoType Dev 证书，已用 ad-hoc 签名"
fi

echo "✅ 已生成: $APP"