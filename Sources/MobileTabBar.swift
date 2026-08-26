import SwiftUI

enum MobileAppTab: Hashable, CaseIterable {
    case today, patterns, reflect, settings

    var title: String {
        switch self {
        case .today:    return "Today"
        case .patterns: return "Patterns"
        case .reflect:  return "Reflect"
        case .settings: return "Settings"
        }
    }

    /// The mockup's own glyphs — a house, a bar chart, a leaf and a gear. The Mac rail's drawn icons
    /// (a trend line, a card, sliders) are a different set; the phone follows its own design.
    var symbol: String {
        switch self {
        case .today:    return "house"
        case .patterns: return "chart.bar"
        case .reflect:  return "leaf"
        case .settings: return "gearshape"
        }
    }
}

/// The design's own tab bar rather than `TabView`'s: the selected item sits on a solid blue plate,
/// which `tabItem` cannot draw, and the bar is the one surface deeper than the page.
struct MobileTabBar: View {
    @Binding var selection: MobileAppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MobileAppTab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .background(alignment: .top) {
            AwairaPalette.sidebar
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AwairaPalette.cardBorder)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ tab: MobileAppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(isSelected ? AwairaPalette.navSelectedText
                                                : AwairaPalette.ink.opacity(0.6))
                    .frame(width: 52, height: 32)
                    .background(isSelected ? AwairaPalette.navSelected : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AwairaPalette.text : AwairaPalette.ink.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.\(tab.title)")
    }
}
