import SwiftUI

/// Declaration order is also the system vertical tab bar's order.
enum DYMainTab: String, CaseIterable, Hashable {
    case mine = "我的", messages = "私信", home = "首页"
}

/// Let the system compress tabs before video actions when its shared vertical
/// column runs out of room. The expanded selector remains a native TabView.
struct DYSystemTabBar: ViewModifier {
    var hidden = false

    func body(content: Content) -> some View {
        content
            .toolbarVisibility(hidden ? .hidden : .visible, for: .tabBar)
            .toolbarVerticalCompressionBehavior(.prefersToolbarItems)
            .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
            .tabBarMinimizeBehavior(.never)
    }
}

/// The current video supplies its existing controls and callbacks; moving
/// these views into the toolbar must not create another player or data model.
struct DYActiveVideoActionsKey: PreferenceKey {
    static var defaultValue: DYVideoToolbarActions? { nil }

    static func reduce(value: inout DYVideoToolbarActions?, nextValue: () -> DYVideoToolbarActions?) {
        if let next = nextValue() { value = next }
    }
}

struct DYVideoToolbarActions {
    let avatar: AnyView
    let like: AnyView
    let comments: AnyView
    let collect: AnyView
    let share: AnyView
}

struct DYNativeVideoActions: View {
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @Environment(\.horizontalSizeClass) private var sizeClass
    let actions: DYVideoToolbarActions?
    let isHidden: Bool
    let onSearch: () -> Void
    @State private var toolbarFrame: CGRect = .zero
    @State private var windowHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .allowsHitTesting(false)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("搜索", systemImage: "magnifyingglass", action: onSearch)
                            .accessibilityIdentifier("douyin.search")
                    }
                    .axisBehavior(.verticalPreferred)
                    .visibilityPriority(.high)
                    .hidden(isHidden)
                    ToolbarItem(placement: .bottomBar) {
                        if verticalEdge != nil, let actions {
                            VStack(spacing: 7) {
                                actions.avatar
                                actions.like
                                actions.comments
                                actions.collect
                                actions.share
                            }
                            .padding(.vertical, 7)
                            .glassEffect(.regular, in: .capsule)
                            // The system still owns the column and native tabs.
                            // Grow only the clear space above the small controls.
                            .frame(height: slotHeight(in: geo), alignment: .bottom)
                            .background(DYToolbarFrameReader { frame, height in
                                toolbarFrame = frame
                                windowHeight = height
                            })
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("douyin.video.actions")
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                    .axisBehavior(.verticalPreferred)
                    .visibilityPriority(.high)
                    .hidden(actions == nil || verticalEdge == nil)
                }
        }
    }

    private func slotHeight(in geo: GeometryProxy) -> CGFloat {
        let top = toolbarFrame.isEmpty ? (sizeClass == .compact ? 232.0 : 184.0) : toolbarFrame.minY
        // A native tab button occupies the bottom 72 pt including the screen
        // margin; keep a 12 pt separation from its collapsed glass circle.
        return max(270, ((windowHeight > 0 ? windowHeight : geo.size.height) - top - 84).rounded(.down))
    }
}

/// Measure our own toolbar host in window coordinates. SwiftUI's `.global`
/// space inside a toolbar is local to its separate hosting view.
private struct DYToolbarFrameReader: UIViewRepresentable {
    let onChange: (CGRect, CGFloat) -> Void
    func makeUIView(context: Context) -> FrameView {
        let view = FrameView()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }
    func updateUIView(_ view: FrameView, context: Context) { view.onChange = onChange }

    final class FrameView: UIView {
        var onChange: ((CGRect, CGFloat) -> Void)?
        private var lastFrame: CGRect = .zero
        override func didMoveToWindow() { super.didMoveToWindow(); reportFrame() }
        override func layoutSubviews() { super.layoutSubviews(); reportFrame() }
        private func reportFrame() {
            guard let window else { return }
            let frame = convert(bounds, to: window)
            guard !frame.isEmpty, frame != lastFrame else { return }
            lastFrame = frame
            let height = window.bounds.height
            DispatchQueue.main.async { [weak self] in self?.onChange?(frame, height) }
        }
    }
}
