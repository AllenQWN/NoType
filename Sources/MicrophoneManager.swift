import Foundation
import AVFoundation
import CoreAudio

/// 一个可用的音频输入设备（麦克风）
struct MicrophoneDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

/// 麦克风设置：枚举系统输入设备、切换当前麦克风、实时电平检测。
/// 录音端（SpeechService 的 AVAudioEngine）用的是系统默认输入设备，因此这里直接
/// 切换「系统默认输入设备」即可让下一次录音使用新麦克风，无需改造录音链路。
final class MicrophoneManager: NSObject, ObservableObject {
    static let shared = MicrophoneManager()

    @Published private(set) var devices: [MicrophoneDevice] = []
    @Published var selectedDeviceID: AudioDeviceID = 0
    @Published private(set) var isMetering = false
    @Published private(set) var level: Float = 0

    private var meterEngine: AVAudioEngine?

    var selectedName: String {
        devices.first(where: { $0.id == selectedDeviceID })?.name ?? "未检测到麦克风"
    }

    // MARK: 设备枚举与切换

    func refresh() {
        devices = Self.allInputDevices()
        let def = Self.defaultInputDeviceID()
        selectedDeviceID = (def != 0 && devices.contains(where: { $0.id == def })) ? def : (devices.first?.id ?? 0)
    }

    func select(_ device: MicrophoneDevice) {
        Self.setDefaultInput(device.id)
        let def = Self.defaultInputDeviceID()
        if def != 0 {
            selectedDeviceID = def
        }
        nlog("切换输入设备到: \(device.name)")
    }

    // MARK: 电平检测

    func startMetering() {
        stopMetering()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            var peak: Float = 0
            if let chs = buffer.floatChannelData {
                let frames = Int(buffer.frameLength)
                let nCh = Int(buffer.format.channelCount)
                for c in 0..<nCh {
                    let ptr = chs[c]
                    for i in 0..<frames {
                        let v = abs(ptr[i])
                        if v > peak { peak = v }
                    }
                }
            }
            let boosted = min(peak * 6.0, 1.0)
            DispatchQueue.main.async {
                self.level = boosted
            }
        }
        engine.prepare()
        do {
            try engine.start()
            meterEngine = engine
            isMetering = true
            nlog("麦克风电平检测已开始")
        } catch {
            nlog("麦克风电平检测启动失败: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
        }
    }

    func stopMetering() {
        meterEngine?.stop()
        meterEngine?.inputNode.removeTap(onBus: 0)
        meterEngine = nil
        isMetering = false
        level = 0
    }

    // MARK: CoreAudio 底层

    static func defaultInputDeviceID() -> AudioDeviceID {
        var dev: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev
        )
        return err == noErr ? dev : 0
    }

    static func setDefaultInput(_ deviceID: AudioDeviceID) {
        var dev = deviceID
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &dev
        )
    }

    static func allInputDevices() -> [MicrophoneDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id -> MicrophoneDevice? in
            guard inputChannelCount(id) > 0 else { return nil }
            return MicrophoneDevice(id: id, name: deviceName(id))
        }
    }

    static func deviceName(_ id: AudioDeviceID) -> String {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        guard err == noErr, let cf = value?.takeRetainedValue() else { return "未知设备" }
        return cf as String
    }

    static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { data.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, data) == noErr else { return 0 }

        // AudioBufferList 布局：mNumberBuffers(4字节) 后，为满足 AudioBuffer 内 mData 指针的
        // 8 字节对齐会补 4 字节 padding，mBuffers 实际从 offset 8 开始。用 MemoryLayout 取真实
        // 偏移与步长，避免手算 padding（之前 offset=4 是错的，会读到 padding 当通道数，导致
        // 所有设备被误判为 0 输入通道而被过滤，设置里就显示「未检测到麦克风」）。
        let nBuffers = Int(data.load(fromByteOffset: 0, as: UInt32.self))
        let buffersOffset = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers) ?? 8
        let bufferStride = MemoryLayout<AudioBuffer>.size
        var total = 0
        for i in 0..<nBuffers {
            let ch = data.load(fromByteOffset: buffersOffset + bufferStride * i, as: UInt32.self)
            total += Int(ch)
        }
        return total
    }
}