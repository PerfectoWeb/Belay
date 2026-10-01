import BelayModules
import SwiftUI

#if BELAY_MAS

/// The App Store build lists what was left behind and ends nothing: its
/// sandbox lets no signal out.
extension OrphanWatchSettings {
    func endAction(_ pid: pid_t, _ name: String, _ startedAt: Date) -> (() -> Void)? { nil }

    func footer(count: Int) -> some View {
        Text("End it in Activity Monitor.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#else

extension OrphanWatchSettings {
    enum Ask {
        case one(OrphanWatcher.Target, name: String)
        case all(count: Int)
    }

    var isAsking: Binding<Bool> {
        Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })
    }

    var alertTitle: String {
        switch asking {
        case .one(_, let name): String(localized: "End \(name)?")
        case .all: String(localized: "End everything left behind?")
        case nil: ""
        }
    }

    var alertMessage: String {
        switch asking {
        case .one:
            String(
                localized: """
                    Belay asks it to quit and does nothing more. Whatever it has \
                    not saved is lost.
                    """)
        case .all(let count):
            String(
                localized: """
                    Processes Belay will ask to quit: \(count). Whatever they \
                    have not saved is lost.
                    """)
        case nil: ""
        }
    }

    func endAction(_ pid: pid_t, _ name: String, _ startedAt: Date) -> (() -> Void)? {
        { asking = .one(OrphanWatcher.Target(pid: pid, startedAt: startedAt), name: name) }
    }

    func confirm() {
        let asked = asking
        asking = nil
        Task { @MainActor in
            switch asked {
            case .one(let target, _): await watcher.end(target)
            case .all: await watcher.endAll()
            case nil: break
            }
        }
    }

    func footer(count: Int) -> some View {
        HStack(spacing: 10) {
            Button("End All") { asking = .all(count: count) }
                .controlSize(.small)
            if watcher.notEnded > 0 {
                Text("Still running after the request: \(watcher.notEnded). Try Activity Monitor.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#endif
