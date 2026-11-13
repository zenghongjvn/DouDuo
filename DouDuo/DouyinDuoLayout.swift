// DouDuo 三姿态：外屏 / 半折叠 / 内屏平放。
// iOS 27.1 用 ArrangementView.overlay（书本：视频 leading、评论 trailing；桌面：视频在上、评论在下）。
// 更低版本回退容器宽度 wide>=700，不读方向、不读 UIScreen。
import SwiftUI

enum DYDuoMetrics {
    /// Full-bleed media and sheets deliberately extend past SwiftUI's safe
    /// area. Their controls still clear the physical home-indicator region.
    static var windowBottomInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0
    }

    static func mediaBottomPadding(_ containerInset: CGFloat) -> CGFloat {
        // The progress line sits 8 pt above its view's bottom. Lift the info
        // and progress together, retaining their existing music/line spacing.
        max(max(containerInset - 16, 8), windowBottomInset - 8)
    }

    static func bottomSafeAreaOverlap(in proxy: GeometryProxy) -> CGFloat {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return 0 }
        let inset = window.safeAreaInsets.bottom
        return min(inset, max(0, proxy.frame(in: .global).maxY - (window.bounds.maxY - inset)))
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

enum DYBottomSheetKind {
    case comments, share, options
}

struct DYSheetDragActions {
    let update: (CGFloat) -> Void
    let finish: (Bool) -> Void
}

extension EnvironmentValues {
    @Entry var dySheetDrag: DYSheetDragActions? = nil
}

/// Shared dismissal arbitration. A vertical scroll that began below the top
/// never becomes a dismissal; a horizontal gesture can close from any row.
struct DYPanelDismissGesture: ViewModifier {
    @Environment(\.dySheetDrag) private var sheetDrag
    var isAtTop = true
    var allowsSwipeRight = false
    var onClose: (() -> Void)?
    @State private var direction: Axis?
    @State private var startedAtTop = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard onClose != nil else { return }
                if direction == nil {
                    startedAtTop = isAtTop
                    direction = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                if direction == .vertical, startedAtTop,
                   value.translation.height > abs(value.translation.width) {
                    sheetDrag?.update(value.translation.height)
                }
            }
            .onEnded { value in
                defer { direction = nil }
                guard let onClose else { return }
                let dx = value.translation.width, dy = value.translation.height
                let right = allowsSwipeRight && direction == .horizontal && dx > abs(dy) * 1.2 &&
                    (dx > 70 || (dx > 25 && value.predictedEndTranslation.width > 160))
                let down = direction == .vertical && startedAtTop && dy > abs(dx) * 1.2 &&
                    (dy > 70 || (dy > 20 && value.predictedEndTranslation.height > 150))
                if right || down { onClose() }
                else { sheetDrag?.finish(false) }
            })
    }
}

extension View {
    func dyBottomSheet<Panel: View>(isPresented: Binding<Bool>, kind: DYBottomSheetKind,
                                   @ViewBuilder content: @escaping () -> Panel) -> some View {
        modifier(DYBottomSheetPresenter(isPresented: isPresented, kind: kind, panel: content))
    }
}

/// Compact presentations reach the display edges. A full-screen presentation
/// supplies modal focus/dismissal; only its bottom panel draws Liquid Glass.
private struct DYBottomSheetPresenter<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let kind: DYBottomSheetKind
    @ViewBuilder var panel: () -> Panel

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            DYEdgeBottomPanel(kind: kind, panel: panel)
                .presentationBackground(.clear)
        }
    }
}

private struct DYEdgeBottomPanel<Panel: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shareContentHeight = DDTheme.shareSheetHeight
    @State private var dragOffset: CGFloat = 0
    let kind: DYBottomSheetKind
    @ViewBuilder var panel: () -> Panel

    var body: some View {
        GeometryReader { geo in
            let panelHeight = kind == .comments
                ? min(geo.size.height, (geo.size.height + geo.safeAreaInsets.bottom) * 0.62)
                : kind == .options ? min(geo.size.height * 0.78, 620)
                : min(geo.size.height, shareContentHeight)
            let trailingHalf = kind != .comments && geo.size.width >= DYDuoMetrics.legacyWideMin
            let panelWidth = trailingHalf ? geo.size.width / 2 : geo.size.width
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: DDTheme.sheetCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: DDTheme.sheetCornerRadius)
            ZStack(alignment: .bottomTrailing) {
                Color.clear.ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    panel()
                        .environment(\.dySheetDrag, DYSheetDragActions(update: { offset in
                            dragOffset = min(panelHeight, max(0, offset))
                        }, finish: { shouldClose in
                            if shouldClose { dismiss() }
                            else { withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { dragOffset = 0 } }
                        }))
                        .onPreferenceChange(DYForwardContentHeightKey.self) { height in
                            if height > 0 { shareContentHeight = height }
                        }
                }
                .frame(width: panelWidth, height: panelHeight, alignment: .top)
                .glassEffect(.regular, in: shape)
                .clipShape(shape)
                .offset(y: dragOffset)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("douyin.sheet.edgeSurface")
            }
        }
        // Respect the keyboard, while the glass reaches the physical edges.
        .ignoresSafeArea(.container)
        .toolbarVerticalBehavior(.disabled)
    }
}

/// Every entry shares the same comment content; the presenter owns its surface.
struct DYCommentSheet: View {
    let bridge: DouyinBridge
    let aweme: DYAweme
    let onClose: () -> Void
    var focus: DYCommentFocus? = nil

    var body: some View {
        DYCommentPanel(bridge: bridge, aweme: aweme, onClose: onClose, focus: focus)
            .toolbarVerticalBehavior(.disabled)
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

    init(_ geo: GeometryProxy, isPresented: Bool, allowsResident: Bool = true,
         paneFraction: CGFloat? = nil) {
        let w = geo.size.width, h = geo.size.height
        resident = allowsResident && DYDuoMetrics.foldIsActive(geo)
        let tableFold = resident && w <= h
        sideBySide = w >= DYDuoMetrics.legacyWideMin || (resident && w > h)
        showsPane = resident || (sideBySide && isPresented)
        // Preserve v1.3.11's comment width. Author panes still split in half.
        let paneW: CGFloat
        if showsPane && sideBySide {
            if let paneFraction {
                paneW = max(0, (w + geo.safeAreaInsets.trailing) * paneFraction - geo.safeAreaInsets.trailing)
            } else {
                paneW = resident ? w * 0.45 : min(380, w * 0.42)
            }
        } else {
            paneW = 0
        }
        let paneH = tableFold ? h * 0.45 : 0
        videoSize = CGSize(width: w - paneW, height: h - paneH)
        trailingInset = geo.safeAreaInsets.trailing
        // Keyboard insets must not be added back to the panel height. Keep the
        // input above the keyboard while the background reaches the screen edge.
        let containerBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0
        let keyboardIsPresented = geo.safeAreaInsets.bottom > containerBottom + 1
        let bottom = keyboardIsPresented ? 0 : min(geo.safeAreaInsets.bottom, containerBottom)
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
    var onBack: () -> Void
    @ViewBuilder var video: (EdgeInsets) -> Video

    var body: some View {
        NavigationStack {
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
                            .overlay(alignment: .leading) {
                                if layout.sideBySide { Color(uiColor: .separator).frame(width: 0.5) }
                            }
                            .offset(x: layout.paneOrigin.x, y: layout.paneOrigin.y)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .background(Color.black.ignoresSafeArea())
                .overlayPreferenceValue(DYActiveVideoActionsKey.self) { actions in
                    DYStandaloneVideoActions(actions: showComments || layout.showsPane ? nil : actions, onBack: onBack)
                }
                .toolbarVisibility(.hidden, for: .tabBar)
                .toolbarVisibility(.visible, for: .navigationBar)
                .toolbarVerticalCompressionBehavior(.prefersToolbarItems)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .animation(.snappy, value: showComments)
                .animation(.snappy, value: layout.resident)
                .dyBottomSheet(isPresented: Binding(
                    get: { showComments && !layout.sideBySide && !layout.resident && aweme != nil },
                    set: { if !layout.sideBySide && !layout.resident { showComments = $0 } }
                ), kind: .comments) {
                    if let aweme {
                        DYCommentSheet(bridge: bridge, aweme: aweme,
                                       onClose: { showComments = false }, focus: focus)
                    }
                }
            }
        }
    }
}
