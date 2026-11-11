import SwiftUI

enum DYMainTab: String, CaseIterable, Hashable {
    case home = "主页", messages = "私信", mine = "我的"
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .messages: "bubble.left.and.bubble.right.fill"
        case .mine: "person.crop.circle.fill"
        }
    }
    var key: String {
        switch self {
        case .home: "home"
        case .messages: "messages"
        case .mine: "mine"
        }
    }
}

extension EnvironmentValues {
    @Entry var duoMainTab: Binding<DYMainTab> = .constant(.home)
    @Entry var duoDockExpanded: Binding<Bool> = .constant(false)
}

/// Every root page installs the same bottom toolbar. UIKit owns its position,
/// capsule, symbol sizing and touch targets; only expansion/selection is app state.
struct DYDockToolbar: ViewModifier {
    let tab: DYMainTab
    @Environment(\.duoMainTab) private var selection
    @Environment(\.duoDockExpanded) private var expanded
    @Environment(\.displayScale) private var scale

    func body(content: Content) -> some View {
        content.toolbar {
            if selection.wrappedValue == tab {
                ToolbarItemGroup(placement: .bottomBar) {
                    if expanded.wrappedValue {
                        ForEach([selection.wrappedValue] + DYMainTab.allCases.filter { $0 != selection.wrappedValue }, id: \.self) { destination in
                            Button {
                                selection.wrappedValue = destination
                                expanded.wrappedValue = false
                            } label: {
                                Label {
                                    Text(destination.rawValue)
                                } icon: {
                                    Image(uiImage: expandedSymbol(destination)).renderingMode(.template)
                                }
                            }
                            .tint(destination == selection.wrappedValue ? .blue : .white)
                            .accessibilityLabel(destination.rawValue)
                            .accessibilityIdentifier("douyin.dock.\(destination.key)")
                        }
                    } else {
                        Button { expanded.wrappedValue = true } label: {
                            Label(selection.wrappedValue.rawValue, systemImage: selection.wrappedValue.symbol)
                        }
                        .tint(.blue)
                        .accessibilityLabel("栏目，\(selection.wrappedValue.rawValue)")
                        .accessibilityIdentifier("douyin.dock")
                    }
                }
                .axisBehavior(.verticalPreferred)
                .visibilityPriority(.high)
            }
        }
    }

    // The vertical system toolbar extracts an image from Label. Include the
    // expanded label in that image, as for the interaction counts. No bar frames.
    private func expandedSymbol(_ destination: DYMainTab) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: 42, height: 52), format: format).image { _ in
            let configuration = UIImage.SymbolConfiguration(pointSize: 25, weight: .medium)
            if let icon = UIImage(systemName: destination.symbol, withConfiguration: configuration) {
                icon.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(at: CGPoint(x: (42 - icon.size.width) / 2, y: 2))
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.white]
            let title = destination.rawValue as NSString
            let size = title.size(withAttributes: attributes)
            title.draw(at: CGPoint(x: (42 - size.width) / 2, y: 37), withAttributes: attributes)
        }.withRenderingMode(.alwaysTemplate)
    }
}
