# 자오선 (Meridian)

세계 여러 나라 언론의 기사를 한곳에서 보는 개인용 뉴스 앱(iOS 26 · iPadOS 26, SwiftUI).
서버는 따로 운영하는 뉴스 수집 서비스이고, 이 저장소에는 **앱만** 있습니다.

> 서버 주소·토큰 같은 연결 정보는 코드에 없습니다. 앱을 처음 열 때 기기에서 입력하거나
> 설정 링크(`meridian://setup?server=…&token=…`)로 넣으며, 기기 키체인에만 저장됩니다.

## 기능

| 영역 | 내용 |
|---|---|
| 화면 | 주요 뉴스(사건 순위) · 주제별(칸반) · 국가별 · 언론사별 · 북마크 · 검색. 아이패드는 사이드바, 아이폰은 탭 막대(스크롤하면 작아짐) |
| 디자인 | iOS 26 리퀴드 글래스(글래스 칩·버튼·카드), 신문체 제목, 다크 모드 |
| 오프라인 | 받은 응답을 기기에 저장해 먼저 그리고, 네트워크로 바꿈. 주요 뉴스 표본 기사 본문은 미리 받아 둠. 북마크·읽음은 오프라인에서도 바로 반영(나중에 전송) |
| 번역 | 설정 › 번역 엔진에서 선택. **Claude(서버, 저장본)**: 막히거나 오프라인이면 Apple 번역으로. **아이폰 기본 번역**: 목록 제목·요약과 본문·사진 설명을 기기 안에서(언어팩 없는 언어의 목록 제목만 서버로). 기사 메뉴에서 다른 엔진으로 다시 번역 가능 |
| AI 요약 | **기기 AI(Apple Intelligence, Foundation Models)** 가 먼저, 안 되면 서버 AI. 기기 AI로 주요 뉴스 브리핑 원고와 나라별 보도 관점 비교 |
| 읽어 주기 | 기사·브리핑을 음성으로. 잠금 화면·이어폰 조작, 탭 막대 위 재생 막대 |
| 알림 | 주요 뉴스 1위가 새 사건으로 바뀔 때, 아침 7시 오늘의 주요 뉴스, 밤 시간 조용히. 조용한 푸시로 위젯 미리 갱신 |
| 위젯 | 홈 화면(작게·중간·크게·아주 크게), 잠금 화면, StandBy. 제어 센터 버튼 |
| Siri·단축어 | "자오선 주요 뉴스 알려줘", "자오선 브리핑 들려줘", 뉴스 검색 |
| 그 밖에 | Spotlight 검색(북마크·읽은 기사), Handoff(원문), 백그라운드 새로고침, 공유, 원문 웹 보기(SwiftUI WebView) |

## 구조

```
ios/
  gen_project.py          Xcode 프로젝트 생성(대상·설정을 바꾸면 다시 실행)
  Config/                 Info.plist, 위젯 Info.plist, 권한(entitlements)
  Meridian/App            진입점, 알림 대리자, 화면 이동(Router)
  Meridian/Core           모델, API 클라이언트·디스크 캐시, 상태(NewsStore), 푸시·백그라운드·Spotlight
  Meridian/Features       기기 AI, 읽어 주기, 단축어
  Meridian/Views          화면
  MeridianWidget/         위젯·제어 센터 버튼
  Shared/                 앱·위젯 공용(키체인 공유 저장소, 주요 뉴스 요약, 공용 단축어)
```

## 빌드

Mac 없이 GitHub Actions에서 빌드합니다.

- `ios/**`를 푸시하면 시뮬레이터 빌드(서명 없음)
- TestFlight: `gh workflow run ios.yml -f testflight=true`
- 저장소 비밀값: `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `APPLE_TEAM_ID`

## 비밀값 지키기

- `.gitignore`: `.env`, `*.p8`, 프로비저닝 파일 등
- CI `비밀값 검사`: gitleaks + 코드 안 서버 주소·토큰 형태 금지
- 로컬 pre-commit: gitleaks + 개인 금지어 목록(저장소 밖)
