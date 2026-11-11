import SwiftUI

/// Lives above the paged feed; scrolling never moves the top navigation away.
struct DYVideoMoreMenu: View {
    let item: DYAweme
    let bridge: DouyinBridge?
    var onToast: ((String) -> Void)?
    var onDislike: (() -> Void)?
    var onSendDanmaku: (() -> Void)?
    var extras: AnyView = AnyView(EmptyView())
    @State private var saving = false

    var body: some View {
        Menu {
            ControlGroup {
                DYForwardMenu(item: item, bridge: bridge, foreground: .white)
                Button(saving ? "保存中…" : "下载", systemImage: "arrow.down.to.line") { save() }
                    .disabled(saving)
                    .accessibilityIdentifier("douyin.save")
            }
            if let onDislike {
                Button("不感兴趣", systemImage: "hand.thumbsdown", role: .destructive, action: onDislike)
                    .accessibilityIdentifier("douyin.dislike")
            }
            if item.images.isEmpty { DYDanmakuOptions(onSend: onSendDanmaku) }
            extras
        } label: {
            Image(systemName: "ellipsis")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("更多")
        .accessibilityIdentifier("douyin.more")
        .modifier(DYForwardPresentation(item: item))
    }

    private func save() {
        guard !saving else { return }
        saving = true
        onToast?("正在保存…")
        Task {
            do {
                try await DYSaver.save(item)
                onToast?(item.images.isEmpty ? "视频已保存到相册" : "图集已保存到相册")
            } catch {
                onToast?("保存失败：\(error.localizedDescription)")
            }
            saving = false
        }
    }
}
