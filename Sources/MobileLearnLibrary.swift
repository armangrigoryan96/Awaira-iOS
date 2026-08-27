import SwiftUI
import WebKit

/// A native index plus the full published Awaira articles in an in-app reader. WebKit keeps its
/// normal cache, and completion is stored locally on the phone so it is never part of analytics.
/// The Learn tab: the published Awaira articles, grouped by the behaviour they cover, opened in an
/// in-app reader.
///
/// This was a stock `List` tinted `.mint` — a colour that exists nowhere else in the app — on iOS's
/// own grouped background rather than the design's page. It is now built from the same page frame
/// and the same cards as every other tab.
struct MobileLearnLibrary: View {
    @State private var completed = MobileLearnReadStore.load()

    var body: some View {
        NavigationStack {
            MobilePage(title: "Learn",
                       subtitle: "Practical, evidence-informed reading on BFRBs and the patterns "
                               + "around them.",
                       accessory: AnyView(MobileBrandRow())) {
                progressCard

                ForEach(MobileLearnTopic.allCases) { topic in
                    let articles = MobileLearnArticle.all.filter { $0.topic == topic }
                    if !articles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            MobileEyebrow(text: topic.rawValue.uppercased())
                            VStack(spacing: 0) {
                                ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                                    NavigationLink(value: article) {
                                        articleRow(article)
                                    }
                                    .buttonStyle(.plain)
                                    if index < articles.count - 1 {
                                        Rectangle()
                                            .fill(AwairaPalette.cardBorder)
                                            .frame(height: 1)
                                            .padding(.leading, 44)
                                    }
                                }
                            }
                            .awairaCard(padding: 0)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .navigationDestination(for: MobileLearnArticle.self) { article in
                MobileArticleReader(article: article, isComplete: completed.contains(article.id)) {
                    completed.insert(article.id)
                    MobileLearnReadStore.save(completed)
                }
            }
        }
        .tint(AwairaPalette.accent)
    }

    /// How far through the library the reader is — the one number that makes a list of thirteen
    /// articles feel like a course rather than a menu.
    private var progressCard: some View {
        let total = MobileLearnArticle.all.count
        let done = completed.count

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                MobileEyebrow(text: "YOUR READING")
                Spacer(minLength: 0)
                Text("\(done) of \(total)")
                    .awairaStat(13)
                    .foregroundStyle(AwairaPalette.ink.opacity(0.65))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AwairaPalette.ink.opacity(0.08))
                    Capsule()
                        .fill(AwairaPalette.accent)
                        .frame(width: total > 0 ? geo.size.width * CGFloat(done) / CGFloat(total) : 0)
                }
            }
            .frame(height: 5)
        }
        .awairaCard()
    }

    private func articleRow(_ article: MobileLearnArticle) -> some View {
        let isComplete = completed.contains(article.id)
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .scaledFont(16)
                .foregroundStyle(isComplete ? AwairaPalette.accent : AwairaPalette.ink.opacity(0.3))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(AwairaPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isComplete ? "Read" : article.summary)
                    .scaledFont(12)
                    .foregroundStyle(isComplete ? AwairaPalette.accent
                                                : AwairaPalette.ink.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(AwairaPalette.ink.opacity(0.28))
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct MobileArticleReader: View {
    let article: MobileLearnArticle
    let isComplete: Bool
    let markComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MobileArticleWebView(url: article.url, onReachedEnd: markComplete)
            Group {
                if isComplete {
                    Button(action: markComplete) {
                        Label("Read", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(AwairaSecondaryButton())
                } else {
                    Button(action: markComplete) {
                        Label("Mark as read", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(AwairaPrimaryButton())
                }
            }
            .padding(14)
            .background(AwairaPalette.sidebar)
            .overlay(alignment: .top) {
                Rectangle().fill(AwairaPalette.cardBorder).frame(height: 1)
            }
        }
        .navigationTitle(article.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MobileArticleWebView: UIViewRepresentable {
    let url: URL
    let onReachedEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onReachedEnd: onReachedEnd) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        controller.add(context.coordinator, name: "awairaRead")
        controller.addUserScript(WKUserScript(source: Self.readCompletionScript,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }

    static let readCompletionScript = """
    (function () {
      var sent = false;
      function check() {
        var root = document.documentElement;
        var height = Math.max(root.scrollHeight, document.body ? document.body.scrollHeight : 0);
        if (!sent && window.scrollY + window.innerHeight >= height - 80) {
          sent = true; window.webkit.messageHandlers.awairaRead.postMessage('complete');
        }
      }
      window.addEventListener('scroll', check, {passive: true});
      window.addEventListener('resize', check); setTimeout(check, 500);
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onReachedEnd: () -> Void
        init(onReachedEnd: @escaping () -> Void) { self.onReachedEnd = onReachedEnd }
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "awairaRead" else { return }
            DispatchQueue.main.async { self.onReachedEnd() }
        }
    }
}

private enum MobileLearnReadStore {
    private static let key = "awaira.learn.completed.v1"
    static func load() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func save(_ values: Set<String>) { UserDefaults.standard.set(Array(values).sorted(), forKey: key) }
}

private enum MobileLearnTopic: String, CaseIterable, Identifiable {
    case gettingStarted = "Getting started"
    case nailBiting = "Nail biting & oral habits"
    case skinPicking = "Skin & acne picking"
    case hairPulling = "Hair pulling"
    case tools = "Tools & support"
    var id: String { rawValue }
}

private struct MobileLearnArticle: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let topic: MobileLearnTopic
    var shortTitle: String { title }
    var url: URL { URL(string: "https://awaira.app/blogs/\(id)")! }

    static let all: [MobileLearnArticle] = [
        .init(id: "what-are-bfrbs", title: "What are BFRBs?", summary: "A plain-language starting point.", topic: .gettingStarted),
        .init(id: "how-to-stop-biting-your-nails", title: "How to stop biting your nails", summary: "Practical strategies for onychophagia.", topic: .nailBiting),
        .init(id: "why-does-nail-biting-feel-good", title: "Why does nail biting feel good?", summary: "Understanding the relief loop.", topic: .nailBiting),
        .init(id: "lip-cheek-biting", title: "Lip and cheek biting", summary: "How to interrupt the automatic loop.", topic: .nailBiting),
        .init(id: "how-to-stop-picking-your-skin", title: "How to stop picking at your skin and face", summary: "Approaches to noticing and interrupting.", topic: .skinPicking),
        .init(id: "acne-picking-acne-excoriee", title: "Acne picking and acne excoriée", summary: "When acne and a picking loop overlap.", topic: .skinPicking),
        .init(id: "skin-picking-vs-acne", title: "Skin picking vs acne", summary: "Signs that a picking loop needs attention.", topic: .skinPicking),
        .init(id: "cuticle-picking", title: "Cuticle picking", summary: "Why hangnails can be hard to leave alone.", topic: .skinPicking),
        .init(id: "how-to-stop-pulling-your-hair-out", title: "How to stop pulling your hair out", summary: "A practical trichotillomania guide.", topic: .hairPulling),
        .init(id: "why-does-trichotillomania-feel-good", title: "Why does trichotillomania feel good?", summary: "The relief loop explained.", topic: .hairPulling),
        .init(id: "eyelash-and-eyebrow-pulling", title: "Eyelash and eyebrow pulling", summary: "What can make this pattern different.", topic: .hairPulling),
        .init(id: "child-pulling-out-hair", title: "When your child pulls their hair", summary: "A calm guide for parents.", topic: .hairPulling),
        .init(id: "best-bfrb-tools-nail-biting-skin-picking", title: "Best BFRB tools", summary: "Comparing practical support tools.", topic: .tools),
    ]
}
