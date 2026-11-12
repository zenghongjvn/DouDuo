import SwiftUI

enum DYMainTab: String, CaseIterable, Hashable {
    case mine = "我的", messages = "私信", home = "首页"

    var symbol: String {
        switch self {
        case .mine: "person.crop.circle.fill"
        case .messages: "bubble.left.and.bubble.right.fill"
        case .home: "house.fill"
        }
    }

    var accessibilityID: String {
        switch self {
        case .mine: "douyin.dock.mine"
        case .messages: "douyin.dock.messages"
        case .home: "douyin.dock.home"
        }
    }
}

extension EnvironmentValues {
    @Entry var duoDockSelection: Binding<DYMainTab>? = nil
    @Entry var duoDockExpanded: Binding<Bool>? = nil
}

/// The system toolbar owns the bottom/right anchor. A single shared capsule
/// provides the reference's vertical expansion; a Menu would open a popover.
struct DYSystemTabBar: ViewModifier {
    @Environment(\.duoDockSelection) private var selection
    @Environment(\.duoDockExpanded) private var expanded
    var hidden = false

    func body(content: Content) -> some View {
        content
            .toolbarVisibility(.hidden, for: .tabBar)
            .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
            .toolbarMinimizationBehavior(.never, for: .bottomBar)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    if let selection, let expanded {
                        DYNavigationDock(selection: selection, expanded: expanded)
                    }
                }
                .axisBehavior(.verticalPreferred)
                .sharedBackgroundVisibility(.hidden)
                .hidden(hidden)
            }
    }
}

private struct DYNavigationDock: View {
    @Binding var selection: DYMainTab
    @Binding var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(DYMainTab.allCases, id: \.self) { tab in
                if expanded || tab == selection {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                            if !expanded { expanded = true }
                            else if tab == selection { expanded = false }
                            else {
                                selection = tab
                                expanded = tab != .home
                            }
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            if expanded {
                                Text(tab.rawValue).font(.caption2.weight(.medium))
                            }
                        }
                        .foregroundStyle(tab == selection ? Color.blue : .white)
                        .frame(width: expanded ? 50 : 44, height: expanded ? 54 : 44)
                        .background {
                            if expanded && tab == selection {
                                Capsule().fill(.black.opacity(0.22))
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityValue(tab == selection ? (expanded ? "已选中，已展开" : "已选中，已收起") : "")
                    .accessibilityIdentifier(tab.accessibilityID)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottom)))
                }
            }
        }
        .padding(expanded ? 3 : 0)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("douyin.dock")
    }
}
