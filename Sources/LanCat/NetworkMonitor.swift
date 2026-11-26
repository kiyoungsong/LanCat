import Foundation
import Network
import SystemConfiguration

enum LinkState: Equatable {
    case connected   // 랜선 연결 + 인터넷 OK
    case noInternet  // 랜선은 연결됐는데 인터넷이 안 됨
    case unplugged   // 이더넷 링크 없음
}

final class NetworkMonitor: ObservableObject {
    @Published private(set) var state: LinkState = .unplugged
    @Published private(set) var interfaceName: String?
    @Published private(set) var ipv4: String?
    @Published private(set) var linkSpeed: String?
    @Published private(set) var router: String?
    @Published private(set) var dns: [String] = []
    @Published private(set) var lastChange = Date()
    /// 팝오버가 열릴 때마다 1씩 올라가요 (등장 애니메이션 트리거)
    @Published var popoverOpenTick = 0

    var onStateChange: ((LinkState, LinkState) -> Void)?

    /// 테스트용: 값이 있으면 실제 상태 대신 이 상태를 보여줘요. nil이면 실제 상태.
    var simulatedState: LinkState? {
        didSet { updateState() }
    }

    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "lancat.network")
    private var ethInterface: NWInterface?
    private var ethernetUp = false
    private var failCount = 0
    private var probeTimer: Timer?
    private var probing = false

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let eth = path.availableInterfaces.first { iface in
                iface.type == .wiredEthernet && NetworkMonitor.isRunning(iface.name)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                let wasUp = self.ethernetUp
                self.ethInterface = eth
                self.ethernetUp = eth != nil
                self.interfaceName = eth?.name
                if !self.ethernetUp { self.failCount = 0 }
                if wasUp != self.ethernetUp { self.failCount = 0 }
                self.refreshDetails()
                self.updateState()
                self.probe()
            }
        }
        pathMonitor.start(queue: queue)
        probeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.probe()
        }
    }

    func refreshNow() {
        refreshDetails()
        probe()
    }

    // MARK: - 인터넷 확인 (이더넷 인터페이스로만 TCP 연결 시도)

    private func probe() {
        guard ethernetUp, let iface = ethInterface else { updateState(); return }
        guard !probing else { return }
        probing = true

        let params = NWParameters.tcp
        params.requiredInterface = iface
        let conn = NWConnection(host: "1.1.1.1", port: 443, using: params)
        var finished = false

        let finish: (Bool) -> Void = { [weak self] ok in
            DispatchQueue.main.async {
                guard let self, !finished else { return }
                finished = true
                conn.cancel()
                self.probing = false
                if ok {
                    self.failCount = 0
                } else {
                    self.failCount += 1
                    // 한 번 실패는 일시적일 수 있어서 3초 뒤 한 번 더 확인
                    if self.failCount == 1 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.probe() }
                    }
                }
                self.updateState()
            }
        }

        conn.stateUpdateHandler = { st in
            switch st {
            case .ready: finish(true)
            case .failed, .waiting: finish(false)
            default: break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { finish(false) }
    }

    private func updateState() {
        let new: LinkState
        if let sim = simulatedState {
            new = sim
        } else if !ethernetUp {
            new = .unplugged
        } else if failCount >= 2 {
            new = .noInternet
        } else {
            new = .connected
        }
        guard new != state else { return }
        let old = state
        state = new
        lastChange = Date()
        onStateChange?(old, new)
    }

    // MARK: - 상세 정보

    private func refreshDetails() {
        let name = interfaceName
        queue.async { [weak self] in
            let ip = name.flatMap { NetworkMonitor.ipv4Address(of: $0) }
            let speed = name.flatMap { NetworkMonitor.linkSpeed(of: $0) }
            var router: String?
            var dns: [String] = []
            if let store = SCDynamicStoreCreate(nil, "LanCat" as CFString, nil, nil) {
                if let v4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
                    router = v4["Router"] as? String
                }
                if let d = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
                    dns = d["ServerAddresses"] as? [String] ?? []
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.ipv4 = ip
                self.linkSpeed = speed
                self.router = router
                self.dns = dns
            }
        }
    }

    static func isRunning(_ name: String) -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return true }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            if String(cString: p.pointee.ifa_name) == name {
                let flags = Int32(p.pointee.ifa_flags)
                return (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            }
            ptr = p.pointee.ifa_next
        }
        return false
    }

    static func ipv4Address(of name: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if String(cString: ifa.ifa_name) == name,
               let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                return String(cString: host)
            }
            ptr = ifa.ifa_next
        }
        return nil
    }

    /// `ifconfig en7`의 media 줄에서 링크 속도를 읽어요. 예: "(1000baseT <full-duplex>)"
    static func linkSpeed(of name: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        p.arguments = [name]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8),
              let line = out.split(separator: "\n").first(where: { $0.contains("media:") }),
              let range = line.range(of: #"\((\d+)base"#, options: .regularExpression) else { return nil }
        let digits = line[range].filter(\.isNumber)
        guard let mbps = Int(digits) else { return nil }
        if mbps >= 1000 {
            let g = Double(mbps) / 1000
            return g == g.rounded() ? "\(Int(g)) Gbps" : String(format: "%.1f Gbps", g)
        }
        return "\(mbps) Mbps"
    }
}
