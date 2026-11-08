import AVFoundation
import MediaPlayer
import Observation

/// 읽어 주기: 기사 본문이나 주요 뉴스 브리핑을 음성으로. 잠금 화면·이어폰 버튼으로 조절된다.
@MainActor @Observable
final class ReadAloud: NSObject {
    static let shared = ReadAloud()

    struct Track: Equatable {
        let title: String
        let subtitle: String
        let chunks: [String]
        let language: String
        let articleID: Int?
    }

    private(set) var track: Track?
    private(set) var index = 0
    private(set) var speaking = false
    private(set) var paused = false
    var rate: Float = UserDefaults.standard.object(forKey: "speechRate") as? Float ?? 0.5

    func setRate(_ r: Float) {
        rate = r
        UserDefaults.standard.set(r, forKey: "speechRate")
    }

    var active: Bool { track != nil }
    var progress: Double {
        guard let t = track, !t.chunks.isEmpty else { return 0 }
        return Double(index) / Double(t.chunks.count)
    }

    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private var commandsReady = false

    override init() {
        super.init()
        synth.delegate = self
    }

    func play(_ t: Track) {
        stop()
        track = t
        index = 0
        configureSession()
        setupCommands()
        speakCurrent()
    }

    func playArticle(_ d: ArticleDetail) {
        let title = d.item.displayTitle
        var chunks = [title]
        chunks.append(contentsOf: d.paragraphs.isEmpty ? [d.item.summary ?? ""] : d.paragraphs)
        let lang = d.item.translated || !d.item.isForeign ? "ko" : (d.item.language ?? "ko")
        play(Track(title: title, subtitle: d.item.source.name, chunks: chunks.filter { !$0.isEmpty },
                   language: lang, articleID: d.item.id))
    }

    func playBriefing(_ digest: Digest, intro: String? = nil) {
        var chunks = [intro ?? "자오선 주요 뉴스입니다. 최근 24시간 동안 여러 나라 언론이 함께 다룬 사건 다섯 가지를 전해 드립니다."]
        for e in digest.top {
            chunks.append("\(e.rank)위. \(e.displayTitle).")
            if let s = e.summary { chunks.append(s) }
        }
        chunks.append("이상 주요 뉴스였습니다.")
        play(Track(title: "주요 뉴스 브리핑", subtitle: "자오선", chunks: chunks, language: "ko", articleID: nil))
    }

    func toggle() {
        if paused { synth.continueSpeaking(); paused = false }
        else if speaking { synth.pauseSpeaking(at: .word); paused = true }
        else if track != nil { speakCurrent() }
        updateNowPlaying()
    }

    func next() {
        guard let t = track, index + 1 < t.chunks.count else { stop(); return }
        synth.stopSpeaking(at: .immediate)
        index += 1
        speakCurrent()
    }

    func previous() {
        synth.stopSpeaking(at: .immediate)
        index = max(0, index - 1)
        speakCurrent()
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        track = nil
        speaking = false
        paused = false
        index = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func speakCurrent() {
        guard let t = track, index < t.chunks.count else { stop(); return }
        let u = AVSpeechUtterance(string: t.chunks[index])
        u.voice = Self.voice(for: t.language)
        u.rate = rate
        u.postUtteranceDelay = 0.25
        speaking = true
        paused = false
        synth.speak(u)
        updateNowPlaying()
    }

    static func voice(for lang: String) -> AVSpeechSynthesisVoice? {
        let code: String = switch lang.prefix(2) {
        case "ko": "ko-KR"
        case "en": "en-US"
        case "ja": "ja-JP"
        case "zh": "zh-CN"
        case "de": "de-DE"
        case "fr": "fr-FR"
        case "ru": "ru-RU"
        case "uk": "uk-UA"
        case "he": "he-IL"
        case "fa": "fa-IR"
        case "hi": "hi-IN"
        default: "ko-KR"
        }
        // 고품질(향상된) 음성이 있으면 그것을
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == code }
            .max { $0.quality.rawValue < $1.quality.rawValue }
        return best ?? AVSpeechSynthesisVoice(language: code)
    }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? s.setActive(true)
    }

    private func setupCommands() {
        guard !commandsReady else { return }
        commandsReady = true
        let c = MPRemoteCommandCenter.shared()
        c.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in ReadAloud.shared.toggle() }; return .success }
        c.playCommand.addTarget { _ in Task { @MainActor in ReadAloud.shared.toggle() }; return .success }
        c.pauseCommand.addTarget { _ in Task { @MainActor in ReadAloud.shared.toggle() }; return .success }
        c.nextTrackCommand.addTarget { _ in Task { @MainActor in ReadAloud.shared.next() }; return .success }
        c.previousTrackCommand.addTarget { _ in Task { @MainActor in ReadAloud.shared.previous() }; return .success }
    }

    private func updateNowPlaying() {
        guard let t = track else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.subtitle,
            MPNowPlayingInfoPropertyPlaybackRate: (speaking && !paused) ? 1.0 : 0.0,
            MPMediaItemPropertyPlaybackDuration: Double(t.chunks.count),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(index),
        ]
    }

    fileprivate func finishedChunk() {
        guard let t = track else { return }
        if index + 1 < t.chunks.count {
            index += 1
            speakCurrent()
        } else {
            stop()
        }
    }
}

extension ReadAloud: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in ReadAloud.shared.finishedChunk() }
    }
}
