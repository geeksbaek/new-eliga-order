import SwiftUI
import AppIntents
import UserNotifications
import UIKit

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var lunchEnabled = false
    @State private var dinnerEnabled = false
    @State private var lunchTime = Date.now
    @State private var dinnerTime = Date.now
    @State private var notificationStatus = "확인 중"
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var errorMessage: String?
    @State private var hasLoaded = false

    private let scheduler = MealNotificationScheduler()
    private let preferences = PreferencesStore()

    var body: some View {
        Form {
            Section("글자 크기") {
                Label("시스템의 Dynamic Type 설정을 따릅니다", systemImage: "textformat.size")
                Text("설정 앱의 디스플레이 및 텍스트 크기에서 변경할 수 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("식사 알림") {
                LabeledContent("알림 권한", value: notificationStatus)

                Toggle("점심 식단 알림", isOn: $lunchEnabled)
                    .onChange(of: lunchEnabled) { _, value in
                        guard hasLoaded else { return }
                        updateNotification(.lunch, enabled: value, time: lunchTime)
                    }
                if lunchEnabled {
                    DatePicker("점심 알림 시각", selection: $lunchTime, displayedComponents: .hourAndMinute)
                        .onChange(of: lunchTime) { _, value in
                            guard hasLoaded else { return }
                            updateNotification(.lunch, enabled: true, time: value)
                        }
                }

                Toggle("저녁 식단 알림", isOn: $dinnerEnabled)
                    .onChange(of: dinnerEnabled) { _, value in
                        guard hasLoaded else { return }
                        updateNotification(.dinner, enabled: value, time: dinnerTime)
                    }
                if dinnerEnabled {
                    DatePicker("저녁 알림 시각", selection: $dinnerTime, displayedComponents: .hourAndMinute)
                        .onChange(of: dinnerTime) { _, value in
                            guard hasLoaded else { return }
                            updateNotification(.dinner, enabled: true, time: value)
                        }
                }

                if notificationAuthorizationStatus == .notDetermined {
                    Button("알림 권한 요청") {
                        Task {
                            do {
                                _ = try await scheduler.requestAuthorization()
                                await load()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                }

                if notificationAuthorizationStatus == .denied {
                    Button("시스템 알림 설정 열기", systemImage: "gear") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }
            }

            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }

            Section("계정") {
                if !store.userIDHint.isEmpty { LabeledContent("로그인 계정", value: store.userIDHint) }
                Button("로그아웃", role: .destructive) {
                    router.reset()
                    store.logout()
                }
            }

            Section("Siri 및 단축어") {
                ShortcutsLink()
                Text("Siri나 단축어에서 오늘 식단과 카페 메뉴를 바로 열 수 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("앱 정보") {
                LabeledContent("버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("웹 앱과 동일한 엘리가 API를 사용하는 SwiftUI 네이티브 클라이언트입니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("설정")
        .task { await load() }
    }

    private func load() async {
        lunchEnabled = preferences.lunchNotificationEnabled
        dinnerEnabled = preferences.dinnerNotificationEnabled
        lunchTime = preferences.lunchTime
        dinnerTime = preferences.dinnerTime
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus
        notificationStatus = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "허용됨"
        case .denied: "허용 안 됨"
        case .notDetermined: "요청 전"
        @unknown default: "알 수 없음"
        }
        await Task.yield()
        hasLoaded = true
    }

    private func updateNotification(_ meal: MealNotificationScheduler.Meal, enabled: Bool, time: Date) {
        if meal == .lunch {
            preferences.lunchNotificationEnabled = enabled
            preferences.lunchTime = time
        } else {
            preferences.dinnerNotificationEnabled = enabled
            preferences.dinnerTime = time
        }
        Task {
            do {
                if enabled {
                    let settings = await UNUserNotificationCenter.current().notificationSettings()
                    let granted: Bool
                    if settings.authorizationStatus == .notDetermined {
                        granted = try await scheduler.requestAuthorization()
                    } else {
                        granted = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
                    }
                    guard granted else { throw SettingsError.notificationsDenied }
                }
                try await scheduler.schedule(meal, at: time, enabled: enabled)
                await load()
            }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private enum SettingsError: LocalizedError {
    case notificationsDenied

    var errorDescription: String? {
        "알림이 허용되지 않았습니다. 시스템 설정에서 엘리가오더 알림을 허용해 주세요."
    }
}
