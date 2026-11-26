import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// 프레임 묶음을 재생하는 뷰 (정지 이미지면 그냥 보여줌)
struct FramePlayer: View {
    let frames: Frames

    var body: some View {
        if frames.isAnimated {
            TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
                frameImage(frames.image(at: ctx.date))
            }
        } else {
            frameImage(frames.images.first)
        }
    }

    @ViewBuilder
    private func frameImage(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ThemeStore
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(store: store)
                .tabItem { Label(L("settings.section.general"), systemImage: "gearshape") }
                .tag(0)
            AppearanceTab(store: store)
                .tabItem { Label(L("settings.title"), systemImage: "paintpalette") }
                .tag(1)
        }
        .padding(16)
        .frame(width: 640, height: 500)
    }
}

/// 일반 탭: 언어, 로그인 시 자동 실행, 아이콘 테두리
private struct GeneralTab: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LanguageRow()
            LaunchAtLoginToggle()
            Toggle(L("settings.outline"), isOn: $store.iconOutline)

            Divider().padding(.vertical, 4)

            UpdateSection()
            Spacer()
            HStack {
                Spacer()
                Text("LanCat \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 꾸미기 탭: 상태를 하나 고르면 그 상태의 메뉴바 아이콘과 팝오버 그림을 나란히 보여줘요
private struct AppearanceTab: View {
    @ObservedObject var store: ThemeStore
    @State private var state: LinkState = .connected

    private let states: [LinkState] = [.connected, .noInternet, .unplugged]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("settings.description"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $state) {
                ForEach(states, id: \.self) { s in
                    Text(label(s)).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("settings.menubarIcon")).font(.headline)
                    SlotCell(store: store, slot: ThemeSlot.icon(for: state))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("settings.popoverImage")).font(.headline)
                    SlotCell(store: store, slot: ThemeSlot.scene(for: state))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(L("settings.removeWhite"), isOn: $store.removeWhiteBackground)
                Toggle(L("settings.trim"), isOn: $store.trimMargins)
                Text(L("settings.trimHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = store.importError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            Spacer(minLength: 0)

            HStack {
                Button(L("settings.openFolder")) { store.openFolder() }
                Spacer()
                Button(L("settings.resetAll")) { store.resetAll() }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func label(_ state: LinkState) -> String {
        switch state {
        case .connected: return L("state.connected")
        case .noInternet: return L("state.noInternet")
        case .unplugged: return L("state.unplugged")
        }
    }
}

private struct SlotCell: View {
    @ObservedObject var store: ThemeStore
    let slot: ThemeSlot
    @State private var dropTargeted = false

    private var cellWidth: CGFloat { slot.kind == .icon ? 240 : 300 }
    private var cellHeight: CGFloat { 170 }

    var body: some View {
        let frames = store.frames(for: slot)
        let custom = store.isCustom(slot)

        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.13))
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(dropTargeted ? Color.accentColor : Color.white.opacity(0.15),
                                  style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: dropTargeted ? [] : [5, 4]))

                if store.importing == slot {
                    ProgressView().controlSize(.small)
                } else if slot.kind == .icon {
                    VStack(spacing: 8) {
                        menubarPreview(frames, dark: true)
                        menubarPreview(frames, dark: false)
                    }
                } else {
                    FramePlayer(frames: frames)
                        .padding(10)
                }
            }
            .frame(width: cellWidth, height: cellHeight)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { store.importImage(from: url, into: slot) }
                }
                return true
            }

            HStack(spacing: 8) {
                Button(L("settings.choose")) { pickFile() }
                if custom {
                    Button(L("settings.default")) { store.reset(slot) }
                }
                Spacer()
                Text(custom ? (frames.isAnimated ? L("settings.badge.customAnimated") : L("settings.badge.custom")) : L("settings.badge.default"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: cellWidth)
        }
    }

    private func menubarPreview(_ frames: Frames, dark: Bool) -> some View {
        let fg = dark ? Color.white : Color.black
        return HStack(spacing: 10) {
            Image(systemName: "wifi")
                .font(.system(size: 12))
                .opacity(0.35)
            FramePlayer(frames: frames)
                .frame(height: 18)
            Image(systemName: "battery.75")
                .font(.system(size: 12))
            Text("14:30")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .frame(maxWidth: 190)
        .background(dark ? Color(white: 0.2) : Color(white: 0.92), in: RoundedRectangle(cornerRadius: 6))
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .webP, .tiff, .bmp]
        panel.allowsMultipleSelection = false
        panel.message = L("settings.panelMessage")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            store.importImage(from: url, into: slot)
        }
    }
}

/// 언어 선택 (바꾸면 재시작 안내)
private struct LanguageRow: View {
    @State private var selection: String = AppLanguage.override ?? "system"
    @State private var changed = false

    var body: some View {
        HStack(spacing: 12) {
            Picker(L("settings.language"), selection: $selection) {
                Text(L("settings.language.system")).tag("system")
                Divider()
                ForEach(AppLanguage.supported) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .frame(width: 280)
            .onChange(of: selection) { value in
                AppLanguage.override = value == "system" ? nil : value
                changed = true
            }

            if changed {
                Text(L("settings.language.restart"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L("settings.language.restartButton")) { AppLanguage.relaunch() }
            }
            Spacer()
        }
    }
}

/// 로그인 시 자동 실행
private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle(L("menu.launchAtLogin"), isOn: $enabled)
            .onChange(of: enabled) { value in
                do {
                    if value {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSSound.beep()
                }
            }
    }
}

/// 업데이트 확인
private struct UpdateSection: View {
    @ObservedObject var updater = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("update.section")).font(.headline)
            Toggle(L("update.autoCheck"), isOn: $updater.autoCheck)
            HStack(spacing: 10) {
                Button(L("update.checkNow")) { updater.check() }
                    .disabled(updater.status == .checking)
                statusView
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch updater.status {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
            Text(L("update.checking")).font(.callout).foregroundStyle(.secondary)
        case .upToDate:
            Text(L("update.upToDate", updater.currentVersion)).font(.callout).foregroundStyle(.secondary)
        case .available:
            Text(L("update.available", updater.latestVersion ?? "")).font(.callout).foregroundStyle(.green)
            Button(L("update.open")) { updater.openReleasePage() }
        case .failed:
            Text(L("update.failed")).font(.callout).foregroundStyle(.orange)
        }
    }
}
