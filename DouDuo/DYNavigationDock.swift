import SwiftUI

/// Declaration order is the system vertical tab bar's visual order.
enum DYMainTab: String, CaseIterable, Hashable {
    case mine = "我的", messages = "私信", home = "首页"
}

/// The native TabView owns the collapsed selection, expanded tabs, material,
/// size and placement. Every root uses the same compression policy.
struct DYSystemTabBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarVisibility(.visible, for: .tabBar)
            .toolbarVerticalCompressionBehavior(.prefersToolbarItems)
            .tabBarMinimizeBehavior(.never)
    }
}
