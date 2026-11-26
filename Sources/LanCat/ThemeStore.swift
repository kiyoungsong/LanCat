import AppKit
import Combine

/// 애니메이션 프레임 묶음 (정지 이미지면 프레임 1장)
struct Frames {
    var images: [NSImage]
    var durations: [TimeInterval]

    var isAnimated: Bool { images.count > 1 }

    /// 지금 시각에 보여줄 프레임
    func image(at date: Date) -> NSImage? {
        guard !images.isEmpty else { return nil }
        guard images.count > 1 else { return images[0] }
        let total = durations.reduce(0, +)
        guard total > 0 else { return images[0] }
        var t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
        for (i, d) in durations.enumerated() {
            if t < d { return images[i] }
            t -= d
        }
        return images.last
    }
}

enum SlotKind { case icon, scene }

/// 사용자가 바꿀 수 있는 이미지 칸 6개 (상태 3개 × 아이콘/팝오버 그림)
enum ThemeSlot: String, CaseIterable, Identifiable {
    case iconOn, iconQ, iconOff, sceneOn, sceneQ, sceneOff

    var id: String { rawValue }

    var kind: SlotKind {
        switch self {
        case .iconOn, .iconQ, .iconOff: return .icon
        case .sceneOn, .sceneQ, .sceneOff: return .scene
        }
    }

    static func icon(for state: LinkState) -> ThemeSlot {
        switch state {
        case .connected: return .iconOn
        case .noInternet: return .iconQ
        case .unplugged: return .iconOff
        }
    }

    static func scene(for state: LinkState) -> ThemeSlot {
        switch state {
        case .connected: return .sceneOn
        case .noInternet: return .sceneQ
        case .unplugged: return .sceneOff
        }
    }
}

struct ImportError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// 기본 이미지와 사용자 이미지를 관리해요.
/// 사용자 이미지는 ~/Library/Application Support/LanCat/Custom/<칸 이름>/ 에
/// 다듬어진 프레임 PNG(0.png, 1.png…)와 frames.json(프레임별 시간)으로 저장돼요.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    /// 이미지가 바뀔 때마다 올라가요 (화면 갱신용)
    @Published private(set) var revision = 0
    @Published private(set) var importing: ThemeSlot?
    @Published var importError: String?

    @Published var removeWhiteBackground: Bool {
        didSet { UserDefaults.standard.set(removeWhiteBackground, forKey: "removeWhiteBG") }
    }

    @Published var trimMargins: Bool {
        didSet { UserDefaults.standard.set(trimMargins, forKey: "trimMargins") }
    }

    @Published var iconOutline: Bool {
        didSet {
            UserDefaults.standard.set(iconOutline, forKey: "iconOutline")
            for slot in ThemeSlot.allCases where slot.kind == .icon { cache[slot] = nil }
            revision += 1
        }
    }

    let baseDir: URL
    private var cache: [ThemeSlot: Frames] = [:]

    private init() {
        let ud = UserDefaults.standard
        ud.register(defaults: ["removeWhiteBG": true, "trimMargins": true, "iconOutline": false])
        removeWhiteBackground = ud.bool(forKey: "removeWhiteBG")
        trimMargins = ud.bool(forKey: "trimMargins")
        iconOutline = ud.bool(forKey: "iconOutline")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDir = support.appendingPathComponent("LanCat/Custom", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    // MARK: - 읽기

    func frames(for slot: ThemeSlot) -> Frames {
        if let cached = cache[slot] { return cached }
        let f = loadCustom(slot) ?? defaultFrames(slot)
        cache[slot] = f
        return f
    }

    func isCustom(_ slot: ThemeSlot) -> Bool {
        FileManager.default.fileExists(atPath: folder(for: slot).appendingPathComponent("frames.json").path)
    }

    private func folder(for slot: ThemeSlot) -> URL {
        baseDir.appendingPathComponent(slot.rawValue, isDirectory: true)
    }

    private func loadCustom(_ slot: ThemeSlot) -> Frames? {
        let dir = folder(for: slot)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("frames.json")),
              let durations = try? JSONDecoder().decode([Double].self, from: data),
              !durations.isEmpty else { return nil }
        var images: [NSImage] = []
        for i in durations.indices {
            guard let img = NSImage(contentsOf: dir.appendingPathComponent("\(i).png")) else { return nil }
            if slot.kind == .icon, let rep = img.representations.first {
                // 아이콘은 레티나용으로 2배 픽셀로 저장돼 있어요 → 18pt 높이로 표시
                img.size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
            }
            img.isTemplate = false
            images.append(img)
        }
        return Frames(images: images, durations: durations)
    }

    private func defaultFrames(_ slot: ThemeSlot) -> Frames {
        let seq: [(String, TimeInterval)]
        switch slot {
        case .iconOn: seq = [("icon_on_0", 3.2), ("icon_on_1", 0.16), ("icon_on_0", 0.25), ("icon_on_1", 0.14)]
        case .iconQ: seq = [("icon_q_0", 1.6), ("icon_q_1", 0.18)]
        case .iconOff: seq = [("icon_off_0", 0.7), ("icon_off_1", 0.7), ("icon_off_2", 1.1)]
        case .sceneOn: seq = [("scene_on", 1)]
        case .sceneQ: seq = [("scene_q", 1)]
        case .sceneOff: seq = [("scene_off", 1)]
        }
        var images: [NSImage] = []
        var durations: [TimeInterval] = []
        for (name, dur) in seq {
            let file = (slot.kind == .icon && iconOutline) ? name + "_dark" : name
            guard let img = Bundle.main.image(forResource: file)?.copy() as? NSImage else { continue }
            if slot.kind == .icon {
                let ratio = img.size.width / max(img.size.height, 1)
                img.size = NSSize(width: 18 * ratio, height: 18)
            }
            img.isTemplate = false
            images.append(img)
            durations.append(dur)
        }
        return Frames(images: images, durations: durations)
    }

    // MARK: - 쓰기

    func importImage(from url: URL, into slot: ThemeSlot) {
        let removeWhite = removeWhiteBackground
        let trim = trimMargins
        importing = slot
        importError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ImageProcessor.process(url: url, kind: slot.kind, removeWhite: removeWhite, trim: trim)
            DispatchQueue.main.async {
                self.importing = nil
                switch result {
                case .failure(let error):
                    self.importError = error.localizedDescription
                case .success(let processed):
                    do {
                        try self.save(processed, into: slot)
                    } catch {
                        self.importError = L("error.save", error.localizedDescription)
                    }
                    self.cache[slot] = nil
                    self.revision += 1
                }
            }
        }
    }

    private func save(_ processed: ProcessedFrames, into slot: ThemeSlot) throws {
        let dir = folder(for: slot)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, cg) in processed.images.enumerated() {
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                throw ImportError(L("error.png"))
            }
            try data.write(to: dir.appendingPathComponent("\(i).png"))
        }
        try JSONEncoder().encode(processed.durations).write(to: dir.appendingPathComponent("frames.json"))
    }

    func reset(_ slot: ThemeSlot) {
        try? FileManager.default.removeItem(at: folder(for: slot))
        cache[slot] = nil
        revision += 1
    }

    func resetAll() {
        for slot in ThemeSlot.allCases {
            try? FileManager.default.removeItem(at: folder(for: slot))
        }
        cache.removeAll()
        importError = nil
        revision += 1
    }

    func openFolder() {
        NSWorkspace.shared.open(baseDir)
    }
}
