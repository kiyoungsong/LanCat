import AppKit
import SwiftUI

private enum Palette {
    static let bg = Color(red: 0.11, green: 0.125, blue: 0.17)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.09)
    static let green = Color(red: 0.25, green: 0.78, blue: 0.38)
    static let orange = Color(red: 0.94, green: 0.55, blue: 0.16)
    static let gray = Color(white: 0.6)
    static let secondary = Color.white.opacity(0.6)
}

struct PopoverView: View {
    @ObservedObject var monitor: NetworkMonitor
    @ObservedObject var store: ThemeStore
    var openSettings: () -> Void = {}
    @ObservedObject var updater = UpdateChecker.shared

    private var accent: Color {
        switch monitor.state {
        case .connected: Palette.green
        case .noInternet: Palette.orange
        case .unplugged: Palette.gray
        }
    }

    private var pillText: String {
        switch monitor.state {
        case .connected: L("popover.pill.connected")
        case .noInternet: L("popover.pill.noInternet")
        case .unplugged: L("popover.pill.unplugged")
        }
    }

    private var title: String {
        switch monitor.state {
        case .connected: L("popover.title.connected")
        case .noInternet: L("popover.title.noInternet")
        case .unplugged: L("popover.title.unplugged")
        }
    }

    private var subtitle: String {
        switch monitor.state {
        case .connected: L("popover.subtitle.connected")
        case .noInternet: L("popover.subtitle.noInternet")
        case .unplugged: L("popover.subtitle.unplugged")
        }
    }

    private var sceneName: String {
        switch monitor.state {
        case .connected: "scene_on"
        case .noInternet: "scene_q"
        case .unplugged: "scene_off"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .center, spacing: 14) {
                scene
                info
            }
            if updater.updateAvailable, let latest = updater.latestVersion {
                Button {
                    updater.openReleasePage()
                } label: {
                    Label(L("popover.updateBanner", latest), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Palette.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            footer
        }
        .padding(20)
        .frame(width: 580)
        .background(Palette.bg)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: monitor.state)
    }

    private var header: some View {
        HStack {
            Text("LanCat")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(pillText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accent.opacity(0.14), in: Capsule())
        }
    }

    private var scene: some View {
        let slot = ThemeSlot.scene(for: monitor.state)
        return AnimatedScene(
            state: monitor.state,
            frames: store.frames(for: slot),
            showEffects: !store.isCustom(slot),
            openTick: monitor.popoverOpenTick
        )
        .id("\(sceneName)-\(store.revision)")
            .transition(.opacity)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                row(L("popover.interface"), monitor.interfaceName ?? "—")
                divider
                row(L("popover.speed"), monitor.linkSpeed ?? "—")
                divider
                row("IP", monitor.ipv4 ?? "—")
                divider
                row(L("popover.gateway"), monitor.router ?? "—")
                divider
                row("DNS", monitor.dns.isEmpty ? "—" : monitor.dns.prefix(2).joined(separator: "\n"))
            }
            .padding(.horizontal, 12)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.stroke, lineWidth: 0.5))

            (Text(L("popover.lastChange.prefix")) + Text(monitor.lastChange, style: .relative) + Text(L("popover.lastChange.suffix")))
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(Palette.stroke).frame(height: 0.5)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 7)
    }

    private var footer: some View {
        HStack {
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(L("popover.networkSettings"), systemImage: "arrow.up.right.square")
            }
            Spacer()
            Button {
                openSettings()
            } label: {
                Label(L("popover.settings"), systemImage: "gearshape")
            }
            Button {
                monitor.refreshNow()
            } label: {
                Label(L("popover.refresh"), systemImage: "arrow.clockwise")
            }
            Button(L("popover.quit")) { NSApp.terminate(nil) }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

/// 팝오버 일러스트: 열릴 때 톡 튀어나오고, 상태별로 계속 살짝 움직여요.
private struct AnimatedScene: View {
    let state: LinkState
    let frames: Frames
    /// 기본 그림일 때만 z, 물음표, 반짝이 효과를 얹어요 (사용자 그림엔 위치가 안 맞을 수 있어서)
    let showEffects: Bool
    let openTick: Int
    @State private var appeared = false

    private let size = CGSize(width: 270, height: 280)

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                if state == .connected {
                    // 공유기 밑으로 은은하게 숨 쉬는 초록 빛
                    Ellipse()
                        .fill(RadialGradient(colors: [Palette.green.opacity(0.35), .clear],
                                             center: .center, startRadius: 0, endRadius: 120))
                        .frame(width: 240, height: 90)
                        .offset(y: 85)
                        .opacity(0.55 + 0.35 * sin(t * 2))
                        .blur(radius: 6)
                }

                illustration(t)

                if showEffects {
                    switch state {
                    case .unplugged: sleepingZs(t)
                    case .noInternet: questionMark(t)
                    case .connected: sparkles(t)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(appeared ? 1 : 0.9, anchor: .bottom)
        .opacity(appeared ? 1 : 0)
        .onAppear { popIn() }
        .onChange(of: openTick) { _ in
            appeared = false
            popIn()
        }
    }

    private func popIn() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { appeared = true }
        }
    }

    @ViewBuilder
    private func illustration(_ t: TimeInterval) -> some View {
        if let img = frames.image(at: Date(timeIntervalSinceReferenceDate: t)) {
            let base = Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
            switch state {
            case .connected:
                // 둥실둥실
                base.offset(y: sin(t * 1.8) * 2.5)
            case .noInternet:
                // 갸웃갸웃
                base.rotationEffect(.degrees(sin(t * 2.2) * 1.3), anchor: .bottom)
            case .unplugged:
                // 새근새근 숨쉬기
                base.scaleEffect(x: 1, y: 1 + 0.014 * sin(t * 1.3), anchor: .bottom)
            }
        }
    }

    private func sleepingZs(_ t: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let phase = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 11 + CGFloat(phase) * 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(x: 18 + phase * 26 + sin(phase * 6) * 4, y: -70 - phase * 50)
                    .opacity(sin(phase * .pi))
            }
        }
    }

    private func questionMark(_ t: TimeInterval) -> some View {
        Text("?")
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(Palette.orange)
            .rotationEffect(.degrees(sin(t * 2.4) * 10))
            .offset(x: 30, y: -108 + sin(t * 3) * 4)
            .shadow(color: Palette.orange.opacity(0.5), radius: 6)
    }

    private func sparkles(_ t: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let phase = (t * 0.45 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                let xs: [CGFloat] = [-70, 62, 96]
                let ys: [CGFloat] = [-60, -95, -20]
                Image(systemName: "sparkle")
                    .font(.system(size: 9 + CGFloat(i) * 2, weight: .bold))
                    .foregroundStyle(Palette.green)
                    .offset(x: xs[i], y: ys[i] - phase * 12)
                    .opacity(sin(phase * .pi) * 0.9)
                    .scaleEffect(0.6 + sin(phase * .pi) * 0.5)
            }
        }
    }
}
