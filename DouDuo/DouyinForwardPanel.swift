import SwiftUI

struct DYForwardContact: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let avatar: String?
    /// 1：个人；2：群聊。
    let kind: Int
}

struct DYForwardPanelAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
}

/// 仅负责原生面板内容。父视图控制视频上方的位置、可用宽度、遮罩和发送确认。
/// 联系人与可用操作均由父视图传入；不在这里读取网页或发送消息。
struct DYNativeForwardPanel: View {
    let contacts: [DYForwardContact]
    let loading: Bool
    let status: String
    let actions: [DYForwardPanelAction]
    let onContact: (DYForwardContact) -> Void
    let onAction: (String) -> Void
    let onClose: () -> Void

    @ScaledMetric(relativeTo: .body) private var itemWidth: CGFloat = 72
    private let avatarSize: CGFloat = 54
    private let inset = WuWeiDesign.Spacing.lg

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if contacts.isEmpty {
                contactStatus
                    .frame(maxWidth: .infinity, minHeight: avatarSize + inset * 2)
                    .padding(.horizontal, inset)
            } else {
                contactRow
                if status.contains("已复制") || status.contains("失败") || status.contains("未发送") || status.contains("合成") || status.contains("保存") {
                    contactStatus
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, inset)
                        .padding(.top, WuWeiDesign.Spacing.md)
                }
            }

            Divider().padding(.top, 14)
            actionRow(actions.filter { ["private", "groups", "other"].contains($0.id) }, colored: true)
                .padding(.vertical, 14)
            Divider()
            actionRow(actions.filter { !["private", "groups", "other"].contains($0.id) }, colored: false)
                .padding(.vertical, 14)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.themeTextPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("douyin.forward.panel")
    }

    private var header: some View {
        ZStack {
            Text("分享至").font(.headline).accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.title3.weight(.medium))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭分享")
                .accessibilityIdentifier("douyin.forward.close")
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
    }

    private var contactRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: WuWeiDesign.Spacing.sm) {
                ForEach(contacts) { contact in
                    Button { onContact(contact) } label: {
                        VStack(spacing: WuWeiDesign.Spacing.sm) {
                            CachedAsyncImage(url: contact.avatar.flatMap(URL.init(string:))) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Color(uiColor: .tertiarySystemFill))
                                    .overlay {
                                        Image(systemName: contact.kind == 2 ? "person.2.fill" : "person.fill")
                                            .font(.title2)
                                            .foregroundStyle(.themeTextSecondary)
                                    }
                            }
                            .frame(width: avatarSize, height: avatarSize)
                            .clipShape(Circle())
                            .accessibilityHidden(true)

                            Text(contact.name)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(width: itemWidth)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(contact.name)
                    .accessibilityHint(contact.kind == 2 ? "选择群聊，确认后发送" : "选择联系人，确认后发送")
                    .accessibilityIdentifier("douyin.forward.contact.\(contact.id)")
                }
            }
            .padding(.horizontal, inset)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var contactStatus: some View {
        HStack(spacing: WuWeiDesign.Spacing.sm) {
            if loading {
                ProgressView()
                    .accessibilityLabel("正在加载分享联系人")
            }
            Text(statusText)
                .font(.body)
                .foregroundStyle(.themeTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, WuWeiDesign.Spacing.sm)
    }

    private var statusText: String {
        if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return status }
        return loading ? "正在加载分享联系人…" : "暂无可分享的联系人"
    }

    private func actionRow(_ row: [DYForwardPanelAction], colored: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: WuWeiDesign.Spacing.sm) {
                ForEach(row) { action in
                    Button { onAction(action.id) } label: {
                        VStack(spacing: WuWeiDesign.Spacing.md) {
                            Image(systemName: action.symbol)
                                .font(.title2.weight(.semibold))
                                .frame(width: avatarSize, height: avatarSize)
                                .foregroundStyle(.white)
                                .background(colored ? (action.id == "private" ? Color(red: 1, green: 0.16, blue: 0.34) : Color.blue) : Color.black.opacity(0.3), in: Circle())
                                .accessibilityHidden(true)
                            Text(action.title)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: itemWidth)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                    .accessibilityIdentifier("douyin.forward.action.\(action.id)")
                }
            }
            .padding(.horizontal, inset)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
