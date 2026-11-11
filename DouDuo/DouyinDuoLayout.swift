// DouDuo 三姿态：外屏 / 半折叠 / 内屏平放。
// iOS 27.1 用 ArrangementView.overlay（书本：视频 leading、评论 trailing；桌面：视频在上、评论在下）。
// 更低版本回退容器宽度 wide>=700，不读方向、不读 UIScreen。
import SwiftUI

enum DYDuoMetrics {
    /// Align full-bleed video chrome to the runtime trailing system column.
    /// Compact chrome and layouts without a trailing column remain unchanged.
    static func actionRailHorizontalOffset(isRegular: Bool, trailingInset: CGFloat,
                                          columnWidth: CGFloat, outerPadding: CGFloat,
                                          opticalLeadingInset: CGFloat = 0) -> CGFloat {
        guard isRegular, trailingInset > 0 else { return 0 }
        return outerPadding + columnWidth / 2 - trailingInset / 2 - opticalLeadingInset
    }

    /// iOS 17–27.0 的宽屏回退，和改版前同一条线。
    static let legacyWideMin: CGFloat = 700

    /// 折痕是否处于激活状态（半折叠）。iOS 27.1 以下恒为 false。
    static func foldIsActive(_ proxy: GeometryProxy) -> Bool {
        #if DEBUG
        // 演示/截图用：模拟器没有物理折痕，用环境变量强制进入半折叠布局
        if ProcessInfo.processInfo.environment["DOUDUO_FOLD"] == "1" { return true }
        #endif
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).contains { $0.isActive }
        }
        return false
    }

    /// 顶栏左移量：合屏时前摄挖孔压在右上，整排往左让出它的宽度，避免「推荐/直播」被啃掉。
    /// 只认靠上且靠右的 occlusion；下方/居中的（如外屏下缘）不动顶栏。
    static func topBarLeftShift(_ proxy: GeometryProxy) -> CGFloat {
        guard #available(iOS 27.1, *) else { return 0 }
        let w = proxy.size.width
        var shift: CGFloat = 0
        for r in proxy.reservedRegions(kind: .occlusion) where r.isActive {
            let f = r.frame
            guard f.height > 1, f.width > 1 else { continue }
            // 顶部 140pt 内、且位于右半边 → 认定为前摄
            if f.minY < 140, f.minX > w * 0.5 {
                shift = max(shift, f.width)
            }
        }
        return min(shift, 56)
    }
}

// MARK: - 折痕 / 摄像头：整组小幅平移，不大挪

private struct DYNudgePref: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// 自定义按钮栏避开 active 的 occlusion（外屏摄像头）和 division（折痕）。
/// 测量放在未平移的布局框上，平移只作用于内容，避免来回抖。
struct DYRailReservedNudge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            DYRailReservedNudgeBox { content }
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private struct DYRailReservedNudgeBox<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var nudge: CGSize = .zero

    var body: some View {
        content()
            .offset(nudge)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: DYNudgePref.self, value: DYReservedNudge.offset(in: proxy))
                }
            }
            .onPreferenceChange(DYNudgePref.self) { new in
                if hypot(new.width - nudge.width, new.height - nudge.height) > 0.5 { nudge = new }
            }
    }
}

@available(iOS 27.1, *)
enum DYReservedNudge {
    /// 在视图自己的坐标里，把和遮挡区相交的部分挪到最近的一侧。摄像头优先向下，符合外屏「小幅下移」。
    static func offset(in proxy: GeometryProxy) -> CGSize {
        let local = CGRect(origin: .zero, size: proxy.size)
        guard local.width > 1, local.height > 1 else { return .zero }
        var box = local
        var acc = CGSize.zero
        for region in proxy.reservedRegions(kind: .occlusion) where region.isActive && region.frame.intersects(box) {
            let d = clear(box, region.frame, preferDown: true)
            acc.width += d.width
            acc.height += d.height
            box = box.offsetBy(dx: d.width, dy: d.height)
        }
        for region in proxy.reservedRegions(kind: .division) where region.isActive && region.frame.intersects(box) {
            let d = clear(box, region.frame, preferDown: false)
            acc.width += d.width
            acc.height += d.height
            box = box.offsetBy(dx: d.width, dy: d.height)
        }
        return acc
    }

    private static func clear(_ box: CGRect, _ region: CGRect, preferDown: Bool) -> CGSize {
        let left = CGSize(width: region.minX - box.maxX, height: 0)
        let right = CGSize(width: region.maxX - box.minX, height: 0)
        let up = CGSize(width: 0, height: region.minY - box.maxY)
        let down = CGSize(width: 0, height: region.maxY - box.minY)
        let mag: (CGSize) -> CGFloat = { abs($0.width) + abs($0.height) }
        let best = [left, right, up, down].min { mag($0) < mag($1) } ?? .zero
        if preferDown, mag(down) <= mag(best) + 24 { return down }
        return best
    }
}

// MARK: - Shared comments presentation

/// Every compact-screen entry uses the same system sheet and one glass surface.
struct DYCommentSheet: View {
    let bridge: DouyinBridge
    let aweme: DYAweme
    let onClose: () -> Void
    var focus: DYCommentFocus? = nil

    var body: some View {
        DYCommentPanel(bridge: bridge, aweme: aweme, onClose: onClose, focus: focus)
            .toolbarVerticalBehavior(.disabled)
            .presentationDetents([.fraction(0.62)])
            .presentationCornerRadius(DDTheme.sheetCornerRadius)
            .presentationDragIndicator(.visible)
    }
}

/// Shared geometry for recommendation, following, profile/search works and
/// comment links from messages. Changing pane size never replaces the pager.
struct DYCommentPaneMetrics {
    let resident: Bool
    let sideBySide: Bool
    let showsPane: Bool
    let videoSize: CGSize
    let paneSize: CGSize
    let paneOrigin: CGPoint
    let trailingInset: CGFloat

    init(_ geo: GeometryProxy, isPresented: Bool, allowsResident: Bool = true) {
        let w = geo.size.width, h = geo.size.height
        resident = allowsResident && DYDuoMetrics.foldIsActive(geo)
        let tableFold = resident && w <= h
        sideBySide = w >= DYDuoMetrics.legacyWideMin || (resident && w > h)
        showsPane = resident || (sideBySide && isPresented)
        let paneW = showsPane && sideBySide ? w * 0.5 : 0
        let paneH = tableFold ? h * 0.45 : 0
        videoSize = CGSize(width: w - paneW, height: h - paneH)
        trailingInset = geo.safeAreaInsets.trailing
        // Keyboard insets must not be added back to the panel height. Keep the
        // input above the keyboard while the background reaches the screen edge.
        let containerBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0
        let bottom = min(geo.safeAreaInsets.bottom, containerBottom)
        paneSize = CGSize(width: sideBySide ? paneW + trailingInset : w,
                          height: tableFold ? paneH : h + geo.safeAreaInsets.top + bottom)
        paneOrigin = CGPoint(x: sideBySide ? videoSize.width : 0,
                             y: tableFold ? videoSize.height : -geo.safeAreaInsets.top)
    }
}

/// Used by the list player opened from My, author/search grids and message links.
struct DYCommentPlayerLayout<Video: View>: View {
    let bridge: DouyinBridge
    let aweme: DYAweme?
    @Binding var showComments: Bool
    var focus: DYCommentFocus? = nil
    @ViewBuilder var video: (EdgeInsets) -> Video

    var body: some View {
        GeometryReader { geo in
            let layout = DYCommentPaneMetrics(geo, isPresented: showComments)
            ZStack(alignment: .topLeading) {
                video(geo.safeAreaInsets)
                    .environment(\.duoInlineVideoNavigation, layout.showsPane)
                    .frame(width: layout.videoSize.width, height: layout.videoSize.height)
                if layout.showsPane, let aweme {
                    DYCommentPanel(bridge: bridge, aweme: aweme,
                                   onClose: layout.resident ? nil : { showComments = false },
                                   focus: focus, fillsPane: true,
                                   trailingInset: layout.trailingInset)
                        .id(aweme.id)
                        .frame(width: layout.paneSize.width, height: layout.paneSize.height)
                        .clipped()
                        .overlay(alignment: .leading) { if layout.sideBySide { Divider() } }
                        .offset(x: layout.paneOrigin.x, y: layout.paneOrigin.y)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(Color.black.ignoresSafeArea())
            .animation(.snappy, value: showComments)
            .animation(.snappy, value: layout.resident)
            .sheet(isPresented: Binding(
                get: { showComments && !layout.sideBySide && !layout.resident && aweme != nil },
                set: { if !layout.sideBySide && !layout.resident { showComments = $0 } }
            )) {
                if let aweme {
                    DYCommentSheet(bridge: bridge, aweme: aweme,
                                   onClose: { showComments = false }, focus: focus)
                }
            }
        }
    }
}
