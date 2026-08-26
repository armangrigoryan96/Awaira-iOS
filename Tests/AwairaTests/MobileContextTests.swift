import XCTest
@testable import Awaira

/// The vocabulary behind the "What was happening?" chips, and the notes filed beside them.
final class MobileContextTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A throwaway suite, so a test never reads or overwrites the real app's answers.
        suiteName = "awaira.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Chips

    func testChipsComeFromTheOnboardingAnswer() {
        defaults.set("Reading,Studying,While thinking", forKey: MobileContextOptions.onboardingKey)

        let labels = MobileContextOptions.choices(defaults: defaults).map(\.label)

        XCTAssertEqual(labels, ["Reading", "Studying", "While thinking", "Other…"])
    }

    func testAUserWhoSkippedTheQuestionStillGetsChips() {
        let labels = MobileContextOptions.choices(defaults: defaults).map(\.label)

        XCTAssertEqual(labels, MobileContextOptions.fallbackLabels + ["Other…"])
    }

    func testTheCardNeverGrowsPastItsSlots() {
        defaults.set("Working on computer,During meetings,While coding,While thinking,Studying,Reading",
                     forKey: MobileContextOptions.onboardingKey)

        let choices = MobileContextOptions.choices(defaults: defaults)

        XCTAssertEqual(choices.count, MobileContextOptions.visibleCount + 1)
        XCTAssertTrue(choices.last!.isOther)
        // The newest answers keep their slot; the earliest roll out.
        XCTAssertEqual(choices.dropLast().map(\.label),
                       ["While coding", "While thinking", "Studying", "Reading"])
    }

    func testACustomLabelJoinsTheChipsAndPushesTheOldestOut() {
        defaults.set("Reading,Studying,While thinking,Working on computer",
                     forKey: MobileContextOptions.onboardingKey)

        let added = MobileContextOptions.addCustomLabel("Piano class", defaults: defaults)

        XCTAssertEqual(added?.label, "Piano class")
        let labels = MobileContextOptions.choices(defaults: defaults).map(\.label)
        XCTAssertEqual(labels, ["Studying", "While thinking", "Working on computer",
                                "Piano class", "Other…"])
    }

    /// Two chips with the same word would split one habit's tally in half.
    func testACustomLabelAlreadyOnOfferResolvesToThatChip() {
        defaults.set("Reading", forKey: MobileContextOptions.onboardingKey)

        let added = MobileContextOptions.addCustomLabel("  reading ", defaults: defaults)

        XCTAssertEqual(added?.id, MobileContextOptions.id(for: "Reading"))
        XCTAssertEqual(MobileContextOptions.customLabels(defaults: defaults), [],
                       "nothing new was stored")
        XCTAssertEqual(MobileContextOptions.choices(defaults: defaults).map(\.label),
                       ["Reading", "Other…"])
    }

    func testBlankCustomLabelsAreRefused() {
        XCTAssertNil(MobileContextOptions.addCustomLabel("   ", defaults: defaults))
        XCTAssertNil(MobileContextOptions.addCustomLabel("\n", defaults: defaults))
        XCTAssertEqual(MobileContextOptions.customLabels(defaults: defaults), [])
    }

    func testIdsIgnoreCaseSpacingAndPunctuation() {
        XCTAssertEqual(MobileContextOptions.id(for: "Piano class"),
                       MobileContextOptions.id(for: "piano  Class!"))
    }

    /// A day filed under a label that has since rolled off the card still has to read as words.
    func testAnIdWithNoChipLeftStillNamesItself() {
        XCTAssertEqual(MobileContextOptions.label(for: "piano-class", defaults: defaults),
                       "Piano class")
        XCTAssertEqual(MobileContextOptions.label(for: MobileContextOptions.otherID,
                                                  defaults: defaults), "Other")
    }

    // MARK: - Storage

    /// An answer belongs to the day the touch happened on, not the day it was answered — the two
    /// differ for a touch just before midnight answered just after it.
    func testAnAnswerIsFiledUnderTheDayOfTheTouch() {
        let store = MobileStatsStore(defaults: defaults)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        store.recordContext("reading", at: yesterday)
        store.recordContext("studying", at: Date())
        store.recordContext("studying", at: Date())

        XCTAssertEqual(store.snapshot().todayContexts, ["studying": 2])
    }

    func testDaysWrittenBeforeContextCountsStillDecode() {
        let dayKey: String = {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }()
        let legacy = """
        {"\(dayKey)":{"interruptions":2,"prevented":0,"pulls":1,"activeSeconds":300,\
        "hourlyInterruptions":[\(Array(repeating: "0", count: 24).joined(separator: ","))]}}
        """
        defaults.set(Data(legacy.utf8), forKey: "awaira.mobile.stats.v1")

        let store = MobileStatsStore(defaults: defaults)
        XCTAssertEqual(store.snapshot().today.interruptions, 2, "the stored day survived")
        XCTAssertEqual(store.snapshot().todayContexts, [:])

        store.recordContext("reading", at: Date())
        XCTAssertEqual(store.snapshot().today.interruptions, 2)
        XCTAssertEqual(store.snapshot().todayContexts, ["reading": 1])
    }

    // MARK: - Notes

    func testNotesAreStoredNewestFirstWithTheirChip() {
        let earlier = Date().addingTimeInterval(-600)
        MobileNotesStore.add("first", context: "reading", at: earlier, defaults: defaults)
        MobileNotesStore.add("second", context: "studying", defaults: defaults)

        let notes = MobileNotesStore.load(defaults: defaults)
        XCTAssertEqual(notes.map(\.text), ["second", "first"])
        XCTAssertEqual(notes.last?.context, "reading")
    }

    /// The card calls this on every answer, note or not — a blank one must not become an entry.
    func testABlankNoteIsNotStored() {
        XCTAssertNil(MobileNotesStore.add("   ", context: "reading", defaults: defaults))
        XCTAssertEqual(MobileNotesStore.load(defaults: defaults).count, 0)
    }

    func testEmptyingANoteDeletesIt() {
        let note = MobileNotesStore.add("something", defaults: defaults)!

        MobileNotesStore.update(note.id, text: "  ", defaults: defaults)

        XCTAssertEqual(MobileNotesStore.load(defaults: defaults).count, 0)
    }
}
