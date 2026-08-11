import Foundation
import VigilCore
import VigilSupport

/// The watching half of `GenericProvider`: FSEvents in, sweeps on a shared
/// timer, and the Tier C gate that keeps a live process from ever being mistaken
/// for a busy one. Split from the actor's own file only because both halves
/// together outgrow the 250-line limit in docs/07.
extension GenericProvider {
    /// Both halves of the machinery are live. Teardown has to clear both.
    var isWatching: Bool { !streams.isEmpty && ticker != nil }
    /// N configured targets, one timer. Asserted by the tests.
    var timerCount: Int { ticker == nil ? 0 : 1 }
    var streamCount: Int { streams.count }

    func rebuildStreams() {
        var wanted: [String: [GenericTarget]] = [:]
        for target in targets where target.isConfigured {
            guard let folder = target.watchedFolder, access.hasAccess(to: folder) else { continue }
            wanted[Self.canonical(folder.resolvingSymlinksInPath().path), default: []].append(target)
        }

        for (path, stream) in streams where wanted[path] == nil {
            stream.stop()
            streams[path] = nil
        }
        followers = wanted.mapValues { $0.map(\.id) }

        for (path, group) in wanted where streams[path] == nil {
            // The shortest latency any target asked for: they share the stream,
            // so the most impatient one sets the pace.
            let latency = group.map(\.latency).min() ?? 1
            do {
                streams[path] = try FileEventStream(
                    root: URL(fileURLWithPath: path), latency: latency, queue: queue
                ) { [weak self] paths in
                    guard let self else { return }
                    Task { await self.handle(changedPaths: paths) }
                }
            } catch {
                Log.providers.error("Generic provider could not watch a folder: \(error, privacy: .public)")
            }
        }
    }

    func handle(changedPaths paths: [String]) {
        let now = clock.now
        var touched: Set<GenericTarget.ID> = []
        // Strictly *under* the folder: FSEvents also reports the watched root
        // itself, including once for its own creation, and a folder coming into
        // existence is not an agent working in it.
        for path in paths.map(Self.canonical) {
            for (folder, ids) in followers where path.hasPrefix(folder + "/") {
                touched.formUnion(ids)
            }
        }
        for id in touched { noteChange(target: id, at: now) }
    }

    /// FSEvents reports `/private/var/…` while `resolvingSymlinksInPath` hands
    /// back `/var/…` for the very same folder, and `/tmp` and `/etc` behave the
    /// same way. Comparing the two forms directly makes a watch on anything
    /// under them match nothing at all, silently — so both sides are compared in
    /// one canonical shape, lexically, without touching the disk per event.
    static func canonical(_ path: String) -> String {
        let prefix = "/private/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count - 1))
    }

    /// A file moved under a watched folder. This is the only path that can
    /// produce `.working`.
    func noteChange(target id: GenericTarget.ID, at now: Date) {
        guard let target = targets.first(where: { $0.id == id }) else { return }
        // `docs/03` Tier C: a named process is context. Here it gates rather than
        // signals — if the agent is gone, whatever touched the folder was not it
        // (an editor saving a file, a build, Spotlight).
        guard isPresent(target) else { return }
        var watch =
            watches[target.session]
            ?? GenericWatch(
                id: target.session,
                target: target.id,
                workspace: target.displayName,
                lastActivityAt: now,
                quietPeriod: target.inferredIdleAfter)
        watch.lastActivityAt = now
        watch.quietPeriod = target.inferredIdleAfter
        watches[target.session] = watch
        report(.working, for: target.session, at: now)
    }

    /// A report routed in from the loopback receiver in `VigilHookBridge`.
    /// See `GenericWebhookReport` for the one-line integration this completes.
    public func ingest(_ webhook: GenericWebhookReport, at date: Date? = nil) {
        let now = date ?? clock.now
        let target = targets.first { $0.webhookIdentifier == webhook.identifier }
        let session = target?.session ?? SessionID("generic:\(webhook.identifier)")
        guard webhook.activity != .ended else { return end(session, at: now) }

        var watch =
            watches[session]
            ?? GenericWatch(
                id: session,
                target: target?.id,
                workspace: webhook.workspace ?? target?.displayName ?? webhook.identifier,
                lastActivityAt: now,
                quietPeriod: target?.inferredIdleAfter ?? 45)
        watch.lastActivityAt = now
        if let workspace = webhook.workspace { watch.workspace = workspace }
        watches[session] = watch
        report(webhook.activity, for: session, at: now)
    }

    func isPresent(_ target: GenericTarget) -> Bool {
        guard let name = target.processName else { return true }
        return ProcessRoster.contains(name, in: liveProcesses)
    }

    // MARK: - Sweeps

    func startTicking() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + Self.tickInterval,
            repeating: Self.tickInterval,
            leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.tick() }
        }
        timer.resume()
        ticker = timer
    }

    func tick() {
        let now = clock.now
        sweepForIdle(now: now)
        tickCount += 1
        guard tickCount.isMultiple(of: 3) else { return }
        sweepForDeadProcesses(now: now)
    }

    func sweepForIdle(now: Date) {
        for (id, watch) in watches where watch.reported == .working {
            guard now.timeIntervalSince(watch.lastActivityAt) > watch.quietPeriod else { continue }
            report(.idle, for: id, at: now)
        }
    }

    /// The safety net: a target whose process has exited ends its session now
    /// instead of waiting out the coordinator's TTL.
    func sweepForDeadProcesses(now: Date) {
        // A scan that could not run leaves the last good answer in place: a
        // syscall hiccup must not read as "every agent just exited".
        if let scanned = roster() { liveProcesses = scanned }
        for target in targets where target.processName != nil {
            guard watches[target.session] != nil, !isPresent(target) else { continue }
            end(target.session, at: now)
        }
    }
}
