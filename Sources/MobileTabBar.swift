import SwiftUI

enum MobileAppTab: Hashable, CaseIterable {
    case today, patterns, learn, journal

    var title: String {
        switch self {
        case .today:    return "Today"
        case .patterns: return "Patterns"
        case .learn:    return "Learn"
        case .journal:  return "Journal"
        }
    }

    /// Filled while selected, outlined otherwise — the one weight change that says "you are here"
    /// without needing a second colour to say it. `square.and.pencil` has no filled twin, so
    /// Journal leans on the plate and the accent alone.
    func symbol(selected: Bool) -> String {
        switch self {
        case .today:    return selected ? "house.fill" : "house"
        case .patterns: return selected ? "chart.bar.fill" : "chart.bar"
        case .learn:    return selected ? "book.fill" : "book"
        case .journal:  return "square.and.pencil"
        }
    }
}

/// The design's own tab bar rather than `TabView`'s, because `tabItem` cannot draw the selected
/// state the design asks for.
///
/// The bar is the *raised* surface above the page, as the Mac's navigation rail is above the
/// workspace, and the selected item is an opening cut through it into the page's own colour. That
/// is the desktop's metaphor exactly.
struct MobileTabBar: View {
    @Binding var selection: MobileAppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MobileAppTab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(alignment: .top) {
            AwairaPalette.sidebar
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AwairaPalette.cardBorder)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.easeInOut(duration: 0.16), value: selection)
    }

    private func item(_ tab: MobileAppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            guard !isSelected else { return }
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol(selected: isSelected))
                    .scaledFont(18, weight: .regular)
                    .foregroundStyle(isSelected ? AwairaPalette.accent : AwairaPalette.ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                Text(tab.title)
                    .scaledFont(11, weight: isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? AwairaPalette.navSelectedText
                                                : AwairaPalette.ink.opacity(0.55))
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            // The cut-out: the selected destination opens into the same canvas as the page above
            // it, outlined by the hairline every other surface in the app is outlined by.
            .background {
                RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous)
                    .fill(AwairaPalette.navSelected)
                    .overlay(
                        RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous)
                            .strokeBorder(AwairaPalette.cardBorder, lineWidth: 1)
                    )
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.\(tab.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
