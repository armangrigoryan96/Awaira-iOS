import SwiftUI

// The pieces every tab shares. Before this file, each page built its own header out of raw
// `.font(.system(size:))` calls and its own selection control out of ad-hoc capsules, which is how
// Patterns ended up with a 39pt title beside Today's 28pt one, and how three different "selected"
// treatments appeared on three screens.

// MARK: - Page scaffold

/// The frame every tab shares: the page's own colour, one gutter, one rhythm between cards, and a
/// header block in the app's voice. Having it in one place is what stops Journal being padded to 16
/// while Patterns is padded to 10.
struct MobilePage<Content: View>: View {
    let title: String
    var subtitle: String?
    /// Pinned above the scrolling content. Today puts its camera switch here; the reading pages
    /// carry only the brand lockup.
    var accessory: AnyView?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // A fixed, opaque header rather than one more row inside the scroll view. Two reasons,
            // both of which the scrolling version got wrong: the page title used to slide up under
            // the status bar and collide with the clock, because nothing opaque sat between them;
            // and Today's camera switch scrolled out of reach, when pausing detection is the one
            // control that has to be available at all times.
            if let accessory {
                accessory
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AwairaPalette.window.ignoresSafeArea(edges: .top))
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    MobilePageTitle(title: title, subtitle: subtitle)
                        .padding(.bottom, 2)
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(AwairaPalette.window.ignoresSafeArea())
    }
}

/// A page's title and the line under it — the phone's equivalent of the Mac's `SectionHeader`.
struct MobilePageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .awairaDisplay()
                .foregroundStyle(AwairaPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle)
                    .awairaSubtitle()
                    .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The brand lockup, identical on every page that shows it.
struct MobileBrandRow<Trailing: View>: View {
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image("logo")
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            Text("Awaira")
                .scaledFont(19, weight: .semibold)
                .foregroundStyle(AwairaPalette.text)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension MobileBrandRow where Trailing == EmptyView {
    init() { self.init(trailing: { EmptyView() }) }
}

// MARK: - Card header

/// The title line inside a card, optionally with a control on its right.
struct MobileCardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .awairaCardTitle()
                    .foregroundStyle(AwairaPalette.text)
                Spacer(minLength: 0)
                trailing()
            }
            if let subtitle {
                Text(subtitle)
                    .awairaCaption()
                    .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension MobileCardHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// An eyebrow above a figure — the small all-caps label the design puts over every headline number.
struct MobileEyebrow: View {
    let text: String
    var tint: Color = AwairaPalette.ink.opacity(0.72)

    var body: some View {
        Text(text)
            .awairaEyebrow()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Segmented control

/// The design's selection control: one capsule track, the chosen segment filled with the accent.
/// Replaces the three hand-rolled versions the phone had — including the one on Patterns that was
/// drawn as two static labels and could not actually be operated.
struct MobileSegmented<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    /// Long ranges ("90 days") need every point of width; two-option controls can afford padding.
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    guard !isSelected else { return }
                    withAnimation(.easeInOut(duration: 0.16)) { selection = option }
                } label: {
                    Text(label(option))
                        .scaledFont(compact ? 11 : 12, weight: .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSelected ? Color.white : AwairaPalette.ink.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 6 : 8)
                        .padding(.horizontal, compact ? 10 : 0)
                        .background(isSelected ? AwairaPalette.accent : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("segment.\(label(option))")
            }
        }
        .padding(3)
        .background(AwairaPalette.window, in: Capsule())
        .overlay(Capsule().strokeBorder(AwairaPalette.cardBorder, lineWidth: 1))
    }
}

// MARK: - Buttons

/// The filled button: accent, white text, the card's own radius. The phone used
/// `.borderedProminent` here, which paints iOS's tint over the design's palette.
struct AwairaPrimaryButton: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(15, weight: .semibold)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(AwairaPalette.accent.opacity(enabled ? 1 : 0.35),
                        in: RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// The quiet button: the page's own colour behind the card hairline.
struct AwairaSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(15, weight: .medium)
            .foregroundStyle(AwairaPalette.ink.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(AwairaPalette.window,
                        in: RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AwairaPalette.cardRadius, style: .continuous)
                    .strokeBorder(AwairaPalette.cardBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// A selectable chip — the context prompt's activity choices.
struct MobileChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .scaledFont(13, weight: .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isSelected ? Color.white : AwairaPalette.ink.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .padding(.horizontal, 8)
                .background(isSelected ? AwairaPalette.accent : AwairaPalette.window, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? .clear : AwairaPalette.cardBorder, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state

/// What a card says when it has nothing to show yet. One treatment, so an empty Journal and an
/// empty heatmap don't disagree about how quiet "nothing here" should look.
struct MobileEmptyNote: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if let symbol {
                Image(systemName: symbol)
                    .scaledFont(14)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.35))
            }
            Text(text)
                .awairaCaption(14)
                .foregroundStyle(AwairaPalette.ink.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
