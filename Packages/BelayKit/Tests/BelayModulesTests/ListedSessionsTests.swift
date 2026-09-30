import Testing

@testable import BelayModules

@Suite("Listed sessions")
struct ListedSessionsTests {
    private let rows = [
        ListedSession(title: "Belay", state: .running),
        ListedSession(title: "Cytrongift", state: .awaiting),
        ListedSession(title: "NovaReach", state: .idle)
    ]

    @Test func aRowIsReadFromItsLabelAndItsBadge() {
        let row = ListedSession(label: "Awaiting input Cytrongift", mark: "Awaiting input")
        #expect(row == ListedSession(title: "Cytrongift", state: .awaiting))
        #expect(ListedSession(label: "Idle Weekly review", mark: "Idle")?.state == .idle)
    }

    @Test func aButtonThatOnlySoundsLikeARowIsNot() {
        #expect(ListedSession(label: "Running 3 agents", mark: "") == nil)
        #expect(ListedSession(label: "Running", mark: "Running") == nil)
        #expect(ListedSession(label: "Thinking Belay", mark: "Running") == nil)
    }

    @Test func aBadgeThatSaysSomethingElseIsStillARow() {
        let row = ListedSession(label: "#601, #142 · Open Belay", mark: "#601, #142 · Open")
        #expect(row == ListedSession(title: "Belay", state: .other))
    }

    @Test func theWayBackIsKnownWhateverTheShownSessionsBadgeSays() {
        var visits = SessionVisits()
        var listed = rows
        listed[0] = ListedSession(title: "Belay", state: .other)
        #expect(visits.next(rows: listed, shown: "Belay") == "Cytrongift")
    }

    @Test func theWindowNamesItsSession() {
        #expect(SessionWindow.shownTitle(from: "Cytrongift - Claude Code") == "Cytrongift")
        #expect(SessionWindow.shownTitle(from: "Cytrongift - A digital exchange") == nil)
        #expect(SessionWindow.shownTitle(from: " - Claude Code") == nil)
    }

    @Test func theWaitingSessionBehindTheWindowIsNext() {
        var visits = SessionVisits()
        #expect(visits.next(rows: rows, shown: "Belay") == "Cytrongift")
    }

    @Test func theSessionOnShowIsNotOpened() {
        var visits = SessionVisits()
        #expect(visits.next(rows: rows, shown: "Cytrongift") == nil)
    }

    @Test func nothingIsOpenedWithoutAWayBack() {
        var visits = SessionVisits()
        #expect(visits.next(rows: rows, shown: nil) == nil)
        #expect(visits.next(rows: rows, shown: "Settings") == nil)
    }

    @Test func aSessionThatWaitsForThePersonIsLeftAlone() {
        var visits = SessionVisits()
        visits.decline("Cytrongift")
        #expect(visits.next(rows: rows, shown: "Belay") == nil)
    }

    @Test func itIsOpenedAgainOnceItHasMovedOn() {
        var visits = SessionVisits()
        visits.decline("Cytrongift")
        var moved = rows
        moved[1] = ListedSession(title: "Cytrongift", state: .running)
        #expect(visits.next(rows: moved, shown: "Belay") == nil)
        #expect(visits.next(rows: rows, shown: "Belay") == "Cytrongift")
    }

    @Test func movingOnCountsEvenWhenNoVisitWasAskedFor() {
        var visits = SessionVisits()
        visits.decline("Cytrongift")
        var moved = rows
        moved[1] = ListedSession(title: "Cytrongift", state: .running)
        visits.notice(moved)
        #expect(visits.next(rows: rows, shown: "Belay") == "Cytrongift")
    }

    @Test func twoSessionsByOneNameAreLeftAlone() {
        var visits = SessionVisits()
        let twins = rows + [ListedSession(title: "Cytrongift", state: .idle)]
        #expect(visits.next(rows: twins, shown: "Belay") == nil)
    }
}
