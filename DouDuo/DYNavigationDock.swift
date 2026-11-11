import SwiftUI

/// Declaration order is the system vertical tab bar's visual order.
enum DYMainTab: String, CaseIterable, Hashable {
    case mine = "我的", messages = "私信", home = "首页"
}

/// Native tabs on the account/message roots. Home uses a system toolbar Menu
/// because TabView has no public API to force its vertical bar to collapse.
struct DYSystemTabBar: ViewModifier {
    var hidden = false
    func body(content: Content) -> some View {
        content
            .toolbarVisibility(hidden ? .hidden : .visible, for: .tabBar)
            .toolbarVerticalCompressionBehavior(.prefersToolbarItems)
            .tabBarMinimizeBehavior(.never)
    }
}

struct DYHomeTabMenu: View {
    @Binding var selection: DYMainTab

    var body: some View {
        Menu("首页", systemImage: "house.fill") {
            Button("我的", systemImage: "person.crop.circle") { selection = .mine }
                .accessibilityIdentifier("douyin.dock.mine")
            Button("私信", systemImage: "bubble.left.and.bubble.right") { selection = .messages }
                .accessibilityIdentifier("douyin.dock.messages")
            Button("首页", systemImage: "house.fill") { selection = .home }
                .accessibilityIdentifier("douyin.dock.current")
        }
        .menuOrder(.fixed)
        .tint(.blue)
        .accessibilityLabel("首页，切换栏目")
        .accessibilityIdentifier("douyin.dock.home")
    }
}

/// The active page supplies its controls and callbacks to the owning container.
/// This keeps all entry points on the same actions without recreating a player.
struct DYActiveVideoRailKey: PreferenceKey {
    static var defaultValue: AnyView? { nil }
    static func reduce(value: inout AnyView?, nextValue: () -> AnyView?) {
        if let next = nextValue() { value = next }
    }
}

struct DYNativeVideoRail: View {
    let rail: AnyView?
    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let rail { rail }
                }
                .axisBehavior(.verticalPreferred)
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
