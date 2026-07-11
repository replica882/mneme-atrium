@preconcurrency import AVFoundation
import Foundation

final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var activeNodeId: String?

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(nodeId: String, text: String) {
        guard UserDefaults.standard.object(forKey: "ttsEnabled") as? Bool ?? true else { return }
        let cleaned = Self.cleanForSpeech(text)
        guard !cleaned.isEmpty else { return }

        stop()
        activeNodeId = nodeId
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = Float(UserDefaults.standard.double(forKey: "ttsRate").nonZeroOrDefault(0.48))
        if let language = Locale.preferredLanguages.first {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        synthesizer.speak(utterance)
    }

    /// R3.4 单词发音：固定英语 voice（系统语音是中文，中文 voice 读英文单词怪腔）。
    /// 不吃 ttsEnabled 开关——用户显式点喇叭就是要听。
    func speakWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = 0.42
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        activeNodeId = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        activeNodeId = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        activeNodeId = nil
    }


    static func cleanForSpeech(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            ("```[\\s\\S]*?```", " "),
            ("`([^`]+)`", "$1"),
            ("!\\[[^\\]]*\\]\\([^\\)]*\\)", " "),
            ("\\[([^\\]]+)\\]\\([^\\)]*\\)", "$1"),
            ("[#>*_~\\-]{1,}", " "),
            ("\\|", " "),
            ("\\n{3,}", "\n\n")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Double {
    func nonZeroOrDefault(_ fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}
