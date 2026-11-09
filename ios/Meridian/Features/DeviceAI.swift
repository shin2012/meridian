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

    /// 기사 요약용 지시. "한국 신문사 편집자" 역할을 주면 작은 기기 모델이 "○○신문은 …라고 보도했다"처럼
    /// 본문에 없는 한국 언론사 이름을 지어내서(예: 우크라이나 УНІАН 기사를 "서울신문은"으로 시작) 역할을 뺐다.
    private static let summarizer = """
    너는 기사 요약 도우미다. 주어진 본문에 있는 내용만 한국어로 요약한다. \
    본문에 나오지 않는 언론사·사람·기관 이름은 절대 쓰지 않는다. 출처를 밝힐 때는 주어진 언론사 이름만 쓴다. \
    한자는 쓰지 않는다. 요약문만 출력한다.
    """

    /// 지어낸 출처를 잡아내는 데 쓰는 한국 언론사 이름(본문·제목·언론사명에 없는데 요약에 나오면 실패로 본다)
    private static let koreanOutlets = [
        "서울신문", "조선일보", "중앙일보", "동아일보", "한겨레", "경향신문", "한국일보", "국민일보", "세계일보",
        "문화일보", "매일경제", "한국경제", "연합뉴스", "뉴시스", "뉴스1", "머니투데이", "이데일리", "헤럴드경제",
        "아시아경제", "파이낸셜뉴스", "KBS", "MBC", "SBS", "JTBC", "YTN", "MBN", "TV조선", "채널A",
    ]

    struct Hallucination: Error {}

    /// 기사 세 문장 요약(본문이 길면 앞부분만: 기기 모델의 문맥 한도 약 4천 토큰)
    static func summarize(title: String, body: String, source: String?) async throws -> String {
        let session = LanguageModelSession(instructions: summarizer)
        let text = String(body.prefix(2800))
        let src = (source?.isEmpty == false) ? source! : "알 수 없음"
        let prompt = "다음 기사를 세 문장 이내로 요약해 줘. 누가, 무엇을, 왜 했는지 드러나게. " +
            "언론사 이름으로 문장을 시작하지 말고 내용부터 써.\n\n언론사: \(src)\n제목: \(title)\n본문: \(text)"
        let r = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.2))
        let out = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let given = title + text + src
        if koreanOutlets.contains(where: { out.contains($0) && !given.contains($0) }) {
            throw Hallucination()   // 부르는 쪽이 서버 AI 요약으로 넘어간다
        }
        return out
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
