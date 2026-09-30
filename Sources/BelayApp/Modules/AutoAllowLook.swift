import BelayModules
import Foundation

/// What one look at the screen came to.
struct AutoAllowLook: Sendable {
    /// The sites of the requests that were answered.
    var approved: [String] = []
    /// Requests the rules leave for the person.
    var held = 0
    /// Requests the rules cover whose button would not go.
    var failed = 0
    /// Requests the person answered before Belay pressed anything.
    var beaten = 0
    var presses = 0
    var seconds: TimeInterval = 0
    /// What came of bringing a waiting session into the window, when
    /// that was tried.
    var reach: Reach?
    var visits: SessionVisits

    enum Reach: String, Sendable {
        /// Opened, and the window put back.
        case returned
        /// The session would not come into the window.
        case closed
        /// Opened, and the window would not go back.
        case stranded
    }

    var isEmpty: Bool { approved.isEmpty && held == 0 && failed == 0 && beaten == 0 }

    mutating func answer(_ seen: [PendingPrompt], rules: AutoAllowRules) {
        for request in seen {
            guard AutoAllowDecision.approves(request.prompt, rules: rules) else {
                held += 1
                continue
            }
            switch request.approve() {
            case .answered(let presses, let seconds):
                approved.append(AutoAllowDecision.subject(of: request.prompt))
                self.presses += presses
                self.seconds += seconds
            case .unanswered(let presses):
                failed += 1
                self.presses += presses
            case .gone:
                beaten += 1
            case .changed:
                held += 1
            }
        }
    }

    /// A session that waits behind the window is brought into it,
    /// answered by the same rules, and the window is put back. One
    /// session a look.
    mutating func reachBehind(
        _ list: SessionList, screen: PromptScreen, rules: AutoAllowRules, patience: TimeInterval
    ) {
        guard let home = list.shown,
            let waiting = visits.next(rows: list.rows, shown: home)
        else { return }
        guard list.open(waiting) else {
            visits.decline(waiting)
            reach = list.open(home) ? .closed : .stranded
            return
        }
        let began = Date()
        var seen = screen.pending()
        while seen.isEmpty, Date().timeIntervalSince(began) < patience {
            Thread.sleep(forTimeInterval: 0.2)
            seen = screen.pending()
        }
        answer(seen, rules: rules)
        // Nothing here for Belay: it waits for the person, and is not
        // opened again until it has moved on.
        if approved.isEmpty { visits.decline(waiting) }
        reach = list.open(home) ? .returned : .stranded
    }
}
