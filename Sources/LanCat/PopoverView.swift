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

    private var accent: Color {
        switch monitor.state {
        case .connected: Palette.green
        case .noInternet: Palette.orange
        case .unplugged: Palette.gray
        }
    }

    private var pillText: String {
        switch monitor.state {
        case .connected: "유선랜 온라인"
        case .noInternet: "인터넷 연결 끊김"
        case .unplugged: "랜선 빠짐"
        }
    }

    private var title: String {
        switch monitor.state {
        case .connected: "연결 잘 되고 있어요"
        case .noInternet: "인터넷이 안 돼요"
        case .unplugged: "랜선이 빠졌어요"
        }
    }

    private var subtitle: String {
        switch monitor.state {
        case .connected: "고양이가 공유기를 지키는 중"
        case .noInternet: "케이블은 꽂혀 있는데 인터넷에 닿지 않아요"
        case .unplugged: "케이블을 꽂으면 고양이가 일어나요"
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
        AnimatedScene(state: monitor.state, imageName: sceneName, openTick: monitor.popoverOpenTick)
            .id(sceneName)
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
                row("인터페이스", monitor.interfaceName ?? "—")
                divider
                row("속도", monitor.linkSpeed ?? "—")
                divider
                row("IP", monitor.ipv4 ?? "—")
                divider
                row("게이트웨이", monitor.router ?? "—")
                divider
                row("DNS", monitor.dns.isEmpty ? "—" : monitor.dns.prefix(2).joined(separator: "\n"))
            }
            .padding(.horizontal, 12)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.stroke, lineWidth: 0.5))

            Text("마지막 변경 \(monitor.lastChange, style: .relative) 전")
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
                Label("네트워크 설정 열기", systemImage: "arrow.up.right.square")
            }
            Spacer()
            Button {
                monitor.refreshNow()
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            Button("종료") { NSApp.terminate(nil) }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

/// 팝오버 일러스트: 열릴 때 톡 튀어나오고, 상태별로 계속 살짝 움직여요.
private struct AnimatedScene: View {
    let state: LinkState
    let imageName: String
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

                switch state {
                case .unplugged: sleepingZs(t)
                case .noInternet: questionMark(t)
                case .connected: sparkles(t)
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
        if let img = Bundle.main.image(forResource: imageName) {
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
