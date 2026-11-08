import SwiftUI
import UserNotifications

struct SettingsScreen: View {
    @Environment(NewsStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ReadAloud.self) private var reader
    @Environment(\.dismiss) private var dismiss
    @State private var ui = UiSettings()
    @State private var prefs = Push.shared.prefs
    @State private var cacheSize = 0
    @State private var push = Push.shared

    private var serverLabel: String {
        #if DEBUG
        if DemoLaunch.active { return "(점검용 서버)" }
        #endif
        return store.account?.server.host() ?? "없음"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("보기 설정") {
                    Picker("처음 화면", selection: $ui.defaultView) {
                        Text("주요 뉴스").tag("event")
                        Text("주제별").tag("timeline")
                        Text("국가별").tag("country")
                        Text("언론사별").tag("source")
                        Text("북마크").tag("bookmark")
                    }
                    Picker("글자 크기", selection: $ui.fontSize) {
                        Text("작게").tag("s"); Text("보통").tag("m"); Text("크게").tag("l")
                    }
                    .pickerStyle(.segmented)
                    Toggle("읽은 기사 숨기기", isOn: $ui.hideRead)
                    Toggle("본문 있는 기사만", isOn: $ui.bodyOnly)
                    Toggle("외국어 기사 한국어로 번역해서 보기", isOn: $ui.translate)
                }

                Section {
                    NavigationLink("국가 순서 · 표시") { CountryOrderScreen(ui: $ui) }
                } footer: {
                    Text("보기 설정은 웹(세계 뉴스)과 같이 씁니다.")
                }

                Section {
                    switch push.status {
                    case .authorized, .provisional, .ephemeral:
                        Toggle("주요 뉴스 1위가 바뀌면", isOn: $prefs.topChange)
                        Toggle("아침 7시 오늘의 주요 뉴스", isOn: $prefs.morning)
                        Toggle("밤 11시~아침 7시에는 알리지 않기", isOn: $prefs.quiet)
                        LabeledContent("상태", value: push.registered ? "서버에 등록됨" : (push.token == nil ? "등록 중…" : "등록 대기"))
                        if let e = push.lastError { Text(e).font(.footnote).foregroundStyle(.red) }
                    case .denied:
                        Button("설정 앱에서 알림 켜기") {
                            if let u = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(u) }
                        }
                    default:
                        Button("알림 받기", systemImage: "bell.badge") { Task { await push.requestPermission() } }
                    }
                } header: {
                    Text("알림")
                } footer: {
                    Text("주요 뉴스는 1시간마다 분석합니다. 같은 사건이 1위를 지키면 다시 알리지 않습니다.")
                }

                Section("AI") {
                    LabeledContent("기기 AI(Apple Intelligence)", value: DeviceAI.availability)
                    LabeledContent("서버 AI", value: "Gemini · 기기 AI가 없을 때")
                    Text("요약은 기기 AI가 먼저 합니다(인터넷 없이, 기사 내용이 기기 밖으로 나가지 않음). 기기 AI를 쓸 수 없거나 실패하면 서버 AI가 요약합니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("읽어 주기") {
                    VStack(alignment: .leading) {
                        Text("말하기 빠르기")
                        Slider(value: Binding(get: { Double(reader.rate) }, set: { reader.setRate(Float($0)) }), in: 0.35...0.65) {
                            Text("빠르기")
                        } minimumValueLabel: { Image(systemName: "tortoise") } maximumValueLabel: { Image(systemName: "hare") }
                    }
                    Text("더 자연스러운 목소리는 설정 › 손쉬운 사용 › 읽기 및 말하기 › 음성에서 한국어 ‘향상된’ 음성을 내려받으면 자동으로 씁니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("저장 공간") {
                    LabeledContent("저장된 기사·목록", value: ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                    Button("저장된 내용 지우기", role: .destructive) {
                        DiskCache.clear()
                        cacheSize = DiskCache.size()
                    }
                }

                Section("서버 연결") {
                    LabeledContent("서버", value: serverLabel)
                    Button("연결 바꾸기") {
                        dismiss()
                        Task { try? await Task.sleep(for: .milliseconds(450)); router.showSetup = true }
                    }
                    Button("연결 끊기", role: .destructive) {
                        Task { if let t = push.token { _ = try? await store.api?.data("DELETE", "devices/\(t)") } }
                        Spotlight.clear()
                        store.disconnect()
                        dismiss()
                    }
                }

                Section {
                    LabeledContent("버전", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", systemImage: "checkmark") {
                        if ui != store.ui { store.saveUi(ui) }
                        if prefs != push.prefs { push.update(prefs) }
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .onAppear {
                ui = store.ui
                prefs = push.prefs
                cacheSize = DiskCache.size()
                push.sync()
            }
        }
    }
}

struct CountryOrderScreen: View {
    @Environment(NewsStore.self) private var store
    @Binding var ui: UiSettings

    private var codes: [String] {
        let all = store.countries.map(\.code)
        let o = ui.order.filter(all.contains)
        return o + all.filter { !o.contains($0) }
    }

    var body: some View {
        List {
            ForEach(codes, id: \.self) { c in
                Toggle(isOn: Binding(get: { !ui.hidden.contains(c) },
                                     set: { on in if on { ui.hidden.removeAll { $0 == c } } else { ui.hidden.append(c) } })) {
                    Text("\(Flag.of(c)) \(store.countryName(c))")
                }
            }
            .onMove { from, to in
                var list = codes
                list.move(fromOffsets: from, toOffset: to)
                ui.order = list
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("국가 순서 · 표시")
    }
}

/// 처음 실행: 서버 주소와 앱 토큰. 설정 링크(meridian://setup?server=…&token=…)로 열면 채워져 있다.
struct SetupView: View {
    @Environment(NewsStore.self) private var store
    @Environment(Router.self) private var router
    @State private var server = ""
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "globe.asia.australia.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.tint)
                            .symbolEffect(.breathe)
                        Text("자오선").font(.system(size: 40, weight: .black, design: .serif))
                        Text("세계를 잇는 하나의 선.\n열다섯 나라 150여 언론사의 오늘을 한곳에서.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    VStack(spacing: 12) {
                        TextField("서버 주소", text: $server)
                            .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(14).glassEffect(.regular, in: .rect(cornerRadius: 16))
                        SecureField("앱 토큰", text: $token)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(14).glassEffect(.regular, in: .rect(cornerRadius: 16))
                        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                        Button {
                            Task { await connect() }
                        } label: {
                            Text(busy ? "연결하는 중…" : "연결").frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(busy || server.isEmpty || token.isEmpty)
                    }
                    .frame(maxWidth: 440)

                    Text("서버 주소와 토큰은 이 기기의 키체인에만 저장됩니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                if store.isConfigured {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기", systemImage: "xmark") { router.showSetup = false } }
                }
            }
        }
        .onAppear(perform: prefill)
        .onChange(of: router.showSetup) { _, _ in prefill() }
        .interactiveDismissDisabled(!store.isConfigured)
    }

    private func prefill() {
        if let p = router.setupPrefill {
            server = p.server
            token = p.token
            router.setupPrefill = nil
            if !server.isEmpty && !token.isEmpty { Task { await connect() } }
        } else if server.isEmpty, let a = store.account {
            server = a.server.absoluteString
        }
    }

    private func connect() async {
        guard let url = Account.normalize(server) else { error = "서버 주소를 확인해 주세요."; return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await store.connect(Account(server: url, token: token.trimmingCharacters(in: .whitespacesAndNewlines)))
            router.showSetup = false
            await Push.shared.requestPermission()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
