import Foundation
import FoundationModels

/// 기기 안 AI(Apple Intelligence의 기본 언어 모델). 인터넷 없이, 서버 비용 없이 요약한다.
/// 기기가 지원하지 않거나 Apple Intelligence가 꺼져 있으면 서버 AI 요약(Gemini)을 쓴다.
@MainActor
enum DeviceAI {
    static var availability: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "사용 가능"
        case .unavailable(let why):
            switch why {
            case .deviceNotEligible: return "이 기기는 지원하지 않음"
            case .appleIntelligenceNotEnabled: return "설정에서 Apple Intelligence를 켜야 함"
            case .modelNotReady: return "모델 내려받는 중"
            @unknown default: return "사용할 수 없음"
            }
        }
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static let editor = """
    너는 한국 신문사의 국제부 편집자다. 주어진 기사만 근거로 한국어로 쓴다. \
    기사에 없는 사실은 덧붙이지 않는다. 한자는 쓰지 않는다. 고유명사는 한국 언론 표기를 따른다.
    """

    /// 기사 세 문장 요약(본문이 길면 앞부분만: 기기 모델의 문맥 한도 약 4천 토큰)
    static func summarize(title: String, body: String) async throws -> String {
        let session = LanguageModelSession(instructions: editor)
        let text = String(body.prefix(2800))
        let prompt = "다음 기사를 세 문장 이내로 요약해 줘. 누가, 무엇을, 왜 했는지 드러나게.\n\n제목: \(title)\n본문: \(text)"
        let r = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.2))
        return r.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 주요 뉴스 다섯 건을 라디오 브리핑 원고로(읽어 주기용)
    static func briefing(_ digest: Digest) async throws -> String {
        let session = LanguageModelSession(instructions: editor + " 라디오 뉴스 진행자처럼 자연스러운 말투로 쓴다.")
        let lines = digest.top.map { "\($0.rank). \($0.displayTitle) — \($0.summary ?? "")" }.joined(separator: "\n")
        let prompt = "다음은 최근 24시간 여러 나라 언론이 함께 다룬 사건 순위다. 1분 분량의 뉴스 브리핑 원고로 이어서 써 줘. " +
            "인사말로 시작하고 순위대로 전해 줘.\n\n" + lines
        let r = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.4))
        return r.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 사건 하나의 배경 설명(이 사건이 왜 중요한지)
    static func explain(_ event: NewsEvent) async throws -> String {
        let session = LanguageModelSession(instructions: editor)
        let samples = event.samples.prefix(4).map { "- [\($0.source.name)] \($0.displayTitle): \($0.summary ?? "")" }
            .joined(separator: "\n")
        let prompt = "사건: \(event.displayTitle)\n요약: \(event.summary ?? "")\n여러 나라 보도:\n\(samples)\n\n" +
            "나라마다 보도 관점이 어떻게 다른지 두세 문장으로 정리해 줘."
        let r = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3))
        return r.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
