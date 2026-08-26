import XCTest
@testable import Awaira

/// The gentle target's starting value. The seed runs once on a fresh install and must never touch
/// a goal the user has already chosen — including one that happens to equal the default.
final class MobileGoalTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A throwaway suite, so a test never reads or overwrites the real app's settings.
        suiteName = "awaira.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testEachOnboardingAnswerSeedsAHigherGoalThanTheOneBelowIt() {
        // The mapping is monotonic by design: a heavier estimate starts higher. It is not a
        // conversion — onboarding counts the habit per day, the dashboard counts approaches per
        // hour — so the ordering is the property worth pinning, not the individual figures.
        let ladder = ["A few times", "Around 10–30", "Around 30–100", "More than 100"]
            .map(MobileGoal.seedRate(from:))
        XCTAssertEqual(ladder, ladder.sorted())
        XCTAssertEqual(Set(ladder).count, ladder.count, "Two answers must not seed the same goal")
    }

    func testEverySeededValueIsOfferedBySettings() {
        // A seeded goal the picker cannot display would leave the row blank and the user unable to
        // get back to it.
        for answer in ["A few times", "Around 10–30", "Around 30–100", "More than 100",
                       "I honestly don't know", nil] {
            XCTAssertTrue(MobileGoal.choices.contains(MobileGoal.seedRate(from: answer)),
                          "\(answer ?? "no answer") seeds a value missing from the picker")
        }
    }

    func testAnUnrecognisedOrMissingAnswerFallsBackToTheDefault() {
        XCTAssertEqual(MobileGoal.seedRate(from: nil), MobileGoal.defaultRate)
        XCTAssertEqual(MobileGoal.seedRate(from: "I honestly don't know"), MobileGoal.defaultRate)
        // An option renamed in a later onboarding must not crash or seed something arbitrary.
        XCTAssertEqual(MobileGoal.seedRate(from: "Roughly a dozen"), MobileGoal.defaultRate)
    }

    func testSeedingWritesTheOnboardingAnswerWhenNoGoalIsStored() {
        defaults.set("More than 100", forKey: "frequencyEstimate")

        MobileGoal.seedIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.double(forKey: MobileGoal.storageKey),
                       MobileGoal.seedRate(from: "More than 100"))
    }

    func testSeedingNeverOverwritesAGoalTheUserHasChosen() {
        defaults.set("More than 100", forKey: "frequencyEstimate")
        defaults.set(3.0, forKey: MobileGoal.storageKey)

        MobileGoal.seedIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.double(forKey: MobileGoal.storageKey), 3.0)
    }

    func testAChosenGoalEqualToTheDefaultIsStillLeftAlone() {
        // The guard is on the key's presence, not on its value — a user who deliberately picked the
        // default must not have it re-seeded to something else on the next launch.
        defaults.set("More than 100", forKey: "frequencyEstimate")
        defaults.set(MobileGoal.defaultRate, forKey: MobileGoal.storageKey)

        MobileGoal.seedIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.double(forKey: MobileGoal.storageKey), MobileGoal.defaultRate)
    }

    func testSeedingIsIdempotent() {
        MobileGoal.seedIfNeeded(defaults: defaults)
        let first = defaults.double(forKey: MobileGoal.storageKey)
        MobileGoal.seedIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.double(forKey: MobileGoal.storageKey), first)
    }
}
