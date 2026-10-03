# NoType

AI-powered voice input for macOS. Press a hotkey, speak naturally, and your words are transcribed, optionally polished by an LLM, then typed into whatever app you're using — no window switching, no copy-paste.

> 简体中文: [README.zh-CN.md](README.zh-CN.md)

## Features

- **Dictate anywhere** — Turn speech into text in any app (Docs, Slack, email, browsers, terminals...).
- **Real-time streaming transcription** — Words appear on a floating voice bar as you speak.
- **AI polish** — Optional, removes filler words, fixes spelling, and formats via an LLM.
- **Translate** — Speak in one language, insert the translation in another.
- **History & stats** — Searchable transcription history and daily/weekly word counts.
- **Offline & online engines** — Local SenseVoice + local LLM for fully offline use, or BYOK cloud APIs.
- **BYOK** — Bring your own API keys; keys are stored locally only.

## Requirements

- macOS 14+ (Apple Silicon)
- Xcode Command Line Tools (for `swiftc`)

## Build

```bash
./build.sh
```

The script compiles all Swift sources with `swiftc`, assembles the app icon, and outputs `NoType.app`. No Xcode project or SPM required.

## Usage

1. Launch **NoType**.
2. Grant permissions when prompted:
   - **Microphone** — to record your voice.
   - **Accessibility** — to insert text into your current app.
   - **Input Monitoring** — to listen for global hotkeys (optional, for custom shortcuts).
3. Press the global hotkey (default: **Fn**) to start/stop dictation.
4. Your transcribed (and optionally polished) text is inserted where your cursor is.

### Configure engines

In **Settings** you can pick offline (local) or online engines:

- **Speech recognition (ASR)**
  - Local: SenseVoice via sherpa-onnx (offline, ~166 MB model).
  - Online: Volcengine (Doubao) streaming ASR, or custom.
- **AI / LLM polish**
  - Local: qwen2.5:7b (offline, ~4.7 GB).
  - Online: OpenAI, DeepSeek, Qwen (Tongyi), Moonshot (Kimi), or any OpenAI-compatible endpoint.

### Keyboard shortcuts

- **Fn** — Dictate (tap to start, tap again to stop).
- Custom global hotkeys (`⌥A`, `⌘1`, `⌃Space`, ...) can be bound to prompts (Dictate / Translate).

## Tech stack

- Swift + SwiftUI + AppKit
- Built directly with `swiftc` (no Xcode / SPM)
- AVAudioEngine recording (16 kHz PCM)
- Text injection via pasteboard + simulated `⌘V` (requires Accessibility)

## License

[MIT](LICENSE)