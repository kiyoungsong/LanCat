import AppKit
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

    private let states: [LinkState] = [.connected, .noInternet, .unplugged]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("이미지 바꾸기")
                    .font(.title2.bold())
                Text("칸에 이미지를 끌어다 놓거나 '선택…'을 눌러 바꿀 수 있어요. PNG, JPG, GIF(움직이는 이미지)를 넣을 수 있고, 여백은 자동으로 잘라내요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    Color.clear.frame(width: 84, height: 1)
                    Text("메뉴바 아이콘").font(.headline)
                    Text("팝오버 그림").font(.headline)
                }
                ForEach(states, id: \.self) { state in
                    GridRow {
                        Text(label(state))
                            .font(.headline)
                            .frame(width: 84, alignment: .leading)
                            .padding(.top, 8)
                        SlotCell(store: store, slot: ThemeSlot.icon(for: state))
                        SlotCell(store: store, slot: ThemeSlot.scene(for: state))
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("새로 넣는 이미지의 흰 배경 자동으로 지우기", isOn: $store.removeWhiteBackground)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("새로 넣는 이미지의 여백 자동으로 잘라내기", isOn: $store.trimMargins)
                    Text("같은 크기 캔버스로 만든 아이콘 세트라면 끄는 게 좋아요. 세 아이콘의 크기와 위치가 서로 맞게 유지돼요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                Toggle("기본 아이콘에 테두리 넣기 (다크 메뉴바에서 더 잘 보여요)", isOn: $store.iconOutline)
            }

            if let error = store.importError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            HStack {
                Button("이미지 폴더 열기") { store.openFolder() }
                Spacer()
                Button("모두 기본값으로") { store.resetAll() }
            }
        }
        .padding(24)
        .frame(width: 660)
    }

    private func label(_ state: LinkState) -> String {
        switch state {
        case .connected: return "연결됨"
        case .noInternet: return "인터넷 없음"
        case .unplugged: return "랜선 빠짐"
        }
    }
}

private struct SlotCell: View {
    @ObservedObject var store: ThemeStore
    let slot: ThemeSlot
    @State private var dropTargeted = false

    private var cellWidth: CGFloat { slot.kind == .icon ? 220 : 260 }
    private var cellHeight: CGFloat { slot.kind == .icon ? 96 : 170 }

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
                Button("선택…") { pickFile() }
                if custom {
                    Button("기본값") { store.reset(slot) }
                }
                Spacer()
                Text(custom ? (frames.isAnimated ? "내 이미지 · 움직임" : "내 이미지") : "기본")
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
        panel.message = "바꿀 이미지를 골라 주세요"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            store.importImage(from: url, into: slot)
        }
    }
}
