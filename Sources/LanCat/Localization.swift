import AppKit

/// 번역 문자열 가져오기 (Resources/<언어>.lproj/Localizable.strings)
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// 형식 문자열 번역 (예: "error.save" = "저장하지 못했어요: %@")
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}

/// 앱 언어 설정. nil이면 macOS 시스템 언어를 따라요.
enum AppLanguage {
    struct Option: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    static let supported: [Option] = [
        Option(code: "ko", name: "한국어"),
        Option(code: "en", name: "English"),
        Option(code: "ja", name: "日本語"),
        Option(code: "zh-Hans", name: "简体中文"),
    ]

    /// 사용자가 직접 고른 언어 (없으면 nil)
    static var override: String? {
        get { (UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String])?.first }
        set {
            if let code = newValue {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            UserDefaults.standard.synchronize()
        }
    }

    /// 앱을 새로 띄우고 지금 앱은 종료 (언어 변경 반영용)
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
