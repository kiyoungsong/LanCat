import AppKit

/// GitHub Releases에서 최신 버전을 확인해요 (자동 업데이트가 아니라 "새 버전 있음" 알림만).
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let repo = "kiyoungsong/LanCat"

    enum Status { case idle, checking, upToDate, available, failed }

    @Published private(set) var status: Status = .idle
    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseURL: URL?

    @Published var autoCheck: Bool {
        didSet { UserDefaults.standard.set(autoCheck, forKey: "autoCheckUpdates") }
    }

    private var timer: Timer?

    private init() {
        UserDefaults.standard.register(defaults: ["autoCheckUpdates": true])
        autoCheck = UserDefaults.standard.bool(forKey: "autoCheckUpdates")
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var updateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return Self.isNewer(latest, than: currentVersion)
    }

    /// 앱 시작 시 한 번, 이후 6시간마다 확인
    func start() {
        if autoCheck { check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            guard let self, self.autoCheck else { return }
            self.check()
        }
    }

    func check() {
        guard status != .checking,
              let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        status = .checking
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LanCat/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, _, _ in
            var tag: String?
            var page: URL?
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let name = json["tag_name"] as? String {
                    tag = name.hasPrefix("v") ? String(name.dropFirst()) : name
                }
                page = (json["html_url"] as? String).flatMap(URL.init(string:))
            }
            DispatchQueue.main.async {
                guard let tag else { self.status = .failed; return }
                self.latestVersion = tag
                self.releaseURL = page ?? URL(string: "https://github.com/\(Self.repo)/releases/latest")
                self.status = self.updateAvailable ? .available : .upToDate
            }
        }.resume()
    }

    func openReleasePage() {
        let url = releaseURL ?? URL(string: "https://github.com/\(Self.repo)/releases/latest")!
        NSWorkspace.shared.open(url)
    }

    /// "1.10.0" > "1.9.2" 처럼 숫자 단위로 비교
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
