//  墨阅 InkReader · InkReader/Services/SpeechService.swift
//  功能：播读 —— AVSpeechSynthesizer 分块朗读，支持开始 / 暂停 / 继续 / 跳句并高亮当前句。
//  要点：长文按 SpeechChunk 切块，避免一次性喂给合成器。

import AVFoundation

// MARK: - 朗读片段

/// 一段要读的文字。
/// 文本书带上全文字符偏移（好跟着跳页），PDF 带上页码（好同步页码），
/// 手选朗读则两个都没有 —— 只管读。
struct SpeechChunk {
    var text: String
    var offset: Int?
    var page: Int?

    /// 给 AVSpeechSynthesisVoice 用的语言；nil 表示让系统自己挑
    var preferredLanguage: String? {
        let cjk = text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value)
        }
        return cjk ? "zh-CN" : nil
    }
}

// MARK: - 播读服务

/// 基于 AVSpeechSynthesizer 的连续播读。
///
/// 刻意**不标 @MainActor**：AVSpeechSynthesizerDelegate 是 ObjC 协议，
/// 标了会导致「Main actor-isolated 方法与非隔离协议要求冲突」的报错。
/// 状态更新统一丢回主队列。
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var chunkIndex = 0
    @Published private(set) var chunkCount = 0
    @Published private(set) var currentText = ""

    private let synthesizer = AVSpeechSynthesizer()
    private var chunks: [SpeechChunk] = []

    /// AVSpeechUtterance.rate：0.0 最慢 ~ 1.0 最快，正常语速约 0.5
    var rate: Float = 0.5
    var pitchMultiplier: Float = 1.0
    var volume: Float = 1.0
    /// 语音标识符，nil = 按每段文字自动挑
    var voiceIdentifier: String?

    var onChunkStart: ((SpeechChunk) -> Void)?
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var availableVoices: [AVSpeechSynthesisVoice] { AVSpeechSynthesisVoice.speechVoices() }

    // MARK: 控制

    func start(_ items: [SpeechChunk]) {
        stop()
        chunks = items.filter { !$0.text.trimmed.isEmpty }
        chunkCount = chunks.count
        guard !chunks.isEmpty else { return }
        configureAudioSession()
        chunkIndex = 0
        isSpeaking = true
        isPaused = false
        speakCurrent()
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    func togglePlayPause() {
        isPaused ? resume() : pause()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        currentText = ""
        chunkIndex = 0
        chunkCount = 0
        chunks = []
    }

    /// 调速/换声时正在读的不打断，下一句才生效
    func apply(rate: Float, pitch: Float = 1.0, voiceIdentifier: String? = nil) {
        self.rate = rate
        self.pitchMultiplier = pitch
        self.voiceIdentifier = voiceIdentifier
    }

    // MARK: 内部

    private func speakCurrent() {
        guard chunkIndex < chunks.count else { finish(); return }
        let chunk = chunks[chunkIndex]
        currentText = chunk.text
        onChunkStart?(chunk)

        let utterance = AVSpeechUtterance(string: chunk.text)
        if let id = voiceIdentifier {
            utterance.voice = AVSpeechSynthesisVoice(identifier: id)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: chunk.preferredLanguage)
        }
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = volume
        synthesizer.speak(utterance)
    }

    private func finish() {
        isSpeaking = false
        isPaused = false
        currentText = ""
        onFinish?()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isSpeaking else { return }
            self.chunkIndex += 1
            self.speakCurrent()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // stop() 已经把状态清干净了，这里什么都不做
    }

    // MARK: 切句

    /// 按标点切句：一句太长会让人听不耐烦，超过 maxLength 再按逗号二次切。
    ///
    /// 偏移按 **UTF-16** 计（和 NSString / NSRange 一致），否则后面拿它去
    /// `TxtPaginator.pageIndex(of:in:)` 反查页码会偏。
    /// - Returns: 带全文偏移的片段（baseOffset 是本段文字在全文中起点）
    static func split(text: String, baseOffset: Int = 0, maxLength: Int = 120) -> [SpeechChunk] {
        var result: [SpeechChunk] = []
        var buffer = ""
        var bufferStart = 0     // 本句起点，相对 text 的 utf16 偏移
        var pos = 0             // 当前字符的 utf16 偏移

        func append(_ piece: String, at offset: Int) {
            let trimmed = piece.trimmed
            guard !trimmed.isEmpty else { return }
            if trimmed.count <= maxLength {
                result.append(SpeechChunk(text: trimmed, offset: offset, page: nil))
                return
            }
            // 太长的按逗号 / 顿号 / 分号断开，别让人一口气听不完
            let chars = Array(trimmed)
            var pieceStart = 0
            for (idx, ch) in chars.enumerated() {
                if "，,、；;：:".contains(ch), idx - pieceStart >= maxLength / 2 {
                    result.append(
                        SpeechChunk(text: String(chars[pieceStart...idx]),
                                    offset: offset + pieceStart,
                                    page: nil)
                    )
                    pieceStart = idx + 1
                }
            }
            if pieceStart < chars.count {
                result.append(
                    SpeechChunk(text: String(chars[pieceStart...]),
                                offset: offset + pieceStart,
                                page: nil)
                )
            }
        }

        func flush() {
            if !buffer.trimmed.isEmpty {
                let lead = buffer.prefix(while: { $0.isWhitespace }).count
                append(buffer, at: baseOffset + bufferStart + lead)
            }
            buffer = ""
        }

        for ch in text {
            buffer.append(ch)
            if "。！？!?；;\n\r".contains(ch) {
                flush()
                // 跳过标点后面的空白/换行，下一句从真正的内容开始
                bufferStart = pos + String(ch).utf16.count
            }
            pos += String(ch).utf16.count
        }
        flush()

        return result
    }
}
