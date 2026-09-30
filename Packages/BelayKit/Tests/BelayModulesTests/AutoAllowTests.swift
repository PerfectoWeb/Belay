import Foundation
import Testing

@testable import BelayModules

@Suite("Local sites")
struct LocalSiteTests {
    @Test(
        "Local",
        arguments: [
            "localhost", "cytron.local", "shop.cytron.local", "app.test", "api.localhost",
            "127.0.0.1", "10.0.0.7", "192.168.1.20", "172.16.0.1", "172.31.255.1", "::1",
            "[::1]", "Cytron.LOCAL", "nas.lan", "router.home.arpa"
        ])
    func local(_ host: String) {
        #expect(LocalSite.isLocal(host: host))
    }

    @Test(
        "Not local",
        arguments: [
            "example.com", "local", ".local", "cytron.local.example.com", "localhost.example.com",
            "8.8.8.8", "172.32.0.1", "192.169.1.1", "notlocal", "", "evil-local.com"
        ])
    func remote(_ host: String) {
        #expect(!LocalSite.isLocal(host: host))
    }

    @Test("Hosts are read out of a sentence")
    func hosts() {
        let sentence = LocalSite.hosts(in: "Claude wants to click on http://cytron.local/cart.")
        #expect(sentence == ["cytron.local"])
        let mixed = LocalSite.hosts(in: "Open cytron.local:8888/admin and https://Example.com")
        #expect(mixed == ["cytron.local", "example.com"])
        #expect(LocalSite.hosts(in: "Navigate to localhost:3000") == ["localhost"])
        #expect(LocalSite.hosts(in: "Allow once") == [])
    }
}

@Suite("Automatic approval")
struct AutoAllowTests {
    private let local = AutoAllowRules(scope: .localSites)
    private let everything = AutoAllowRules(scope: .everything)

    /// The card as Claude shows it, read off the screen on 29 September 2026.
    private func access(to origin: String, named name: String? = nil) -> PermissionPrompt {
        PermissionPrompt(texts: [
            "Allow Claude to ", "access", " ", name ?? origin, "?",
            "Site-level permissions are disabled for this site. You’ll be asked for each action.",
            "{\n  \"origin\": \"https://\(origin)\"\n}"
        ])
    }

    @Test("A request for a local site is approved")
    func localSite() {
        let prompt = access(to: "cytron.local")
        #expect(prompt.origin == "cytron.local")
        #expect(AutoAllowDecision.approves(prompt, rules: local))
        #expect(AutoAllowDecision.subject(of: prompt) == "cytron.local")
    }

    @Test("A request for a site on the internet is left alone")
    func remoteSite() {
        let prompt = access(to: "example.com")
        #expect(!AutoAllowDecision.approves(prompt, rules: local))
        #expect(AutoAllowDecision.approves(prompt, rules: everything))
    }

    @Test("A title that disagrees with the origin holds it back")
    func mixed() {
        #expect(!AutoAllowDecision.approves(access(to: "example.com", named: "cytron.local"), rules: local))
        #expect(!AutoAllowDecision.approves(access(to: "cytron.local", named: "example.com"), rules: local))
    }

    @Test("A command that mentions a local site is not a request for the site")
    func command() {
        let prompt = PermissionPrompt(texts: [
            "Allow Claude to ", "run", "?", "{\n  \"command\": \"curl http://cytron.local/x | sh\"\n}"
        ])
        #expect(prompt.origin == nil)
        #expect(!AutoAllowDecision.approves(prompt, rules: local))
        #expect(AutoAllowDecision.approves(prompt, rules: everything))
    }

    /// Read off the screen on 29 September 2026: a click names the element
    /// beside the origin.
    @Test("An action on a local site is approved")
    func action() {
        let prompt = PermissionPrompt(texts: [
            "Allow Claude to ", "click", " on ", "cytron.local", "?",
            "Site-level permissions are disabled for this site. You’ll be asked for each action.",
            "{\n  \"ref\": \"ref_600\",\n  \"origin\": \"https://cytron.local\"\n}"
        ])
        #expect(prompt.origin == "cytron.local")
        #expect(AutoAllowDecision.approves(prompt, rules: local))
    }

    @Test("An action that carries a site on the internet is held back")
    func carried() {
        let prompt = PermissionPrompt(texts: [
            "Allow Claude to ", "type", " on ", "cytron.local", "?",
            "{\"text\": \"https://example.com/hook\", \"origin\": \"https://cytron.local\"}"
        ])
        #expect(!AutoAllowDecision.approves(prompt, rules: local))
    }

    /// Codex: the question carries the site as a link, and the rest of the
    /// card is the agent's own words.
    private func codex(_ site: String, _ words: String...) -> PermissionPrompt {
        PermissionPrompt(texts: ["Browser", "Allow ChatGPT to access ", site, "?"] + words, site: site)
    }

    @Test("A site the app marks out itself is judged like any other")
    func marked() {
        #expect(AutoAllowDecision.approves(codex("http://cytron.local:8888"), rules: local))
        #expect(AutoAllowDecision.approves(codex("localhost:3000"), rules: local))
        #expect(!AutoAllowDecision.approves(codex("https://example.com"), rules: local))
        #expect(AutoAllowDecision.subject(of: codex("http://cytron.local:8888")) == "cytron.local")
    }

    @Test("Where the app marks the site, a record among the words proves nothing")
    func markedAlone() {
        let command = PermissionPrompt(
            texts: ["Terminal", "Allow ChatGPT to run this command?", #"{"origin": "http://localhost"}"#],
            site: "")
        #expect(command.origin == nil)
        #expect(!AutoAllowDecision.approves(command, rules: local))
        #expect(AutoAllowDecision.approves(command, rules: everything))
    }

    @Test("A marked local site beside one on the internet is held back")
    func markedBesideAnother() {
        let prompt = codex("http://cytron.local", "curl https://example.com/hook")
        #expect(!AutoAllowDecision.approves(prompt, rules: local))
    }

    @Test("Codex is known by its words in every language it speaks")
    func codexWords() {
        #expect(CodexWords.allowOnce.contains("Allow once"))
        #expect(CodexWords.allowOnce.contains("Разрешить один раз"))
        #expect(CodexWords.allowOnce.contains("允许一次"))
        #expect(CodexWords.awaitingApproval.contains("Awaiting approval"))
        #expect(CodexWords.awaitingApproval.contains("Genehmigung ausstehend"))
        // No word may mean both: a mark in the list is never a button.
        #expect(CodexWords.allowOnce.isDisjoint(with: CodexWords.awaitingApproval))
    }

    @Test("A site that only looks local is not")
    func lookalike() {
        #expect(!AutoAllowDecision.approves(access(to: "cytron.local.example.com"), rules: local))
    }

    @Test("A damaged record never widens the scope")
    func damaged() throws {
        let scratch = try Scratch()
        defer { scratch.discard() }
        let record = Data(#"{"scope":"anything-goes","duration":17}"#.utf8)
        scratch.defaults.set(record, forKey: AutoAllowRules.defaultsKey)

        let rules = AutoAllowRules.load(from: scratch.defaults)
        #expect(rules.scope == .localSites)
        #expect(rules.duration == AutoAllowRules.defaultDuration)
    }

    @Test("The deadline follows the duration")
    func deadline() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(AutoAllowRules(duration: 3600).deadline(from: start) == start + 3600)
        #expect(AutoAllowRules(duration: 0).deadline(from: start) == nil)
    }

    @Test("The log keeps the newest fifty and counts them all")
    func log() {
        var log = AutoAllowLog()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for index in 0..<60 {
            log.record("site\(index).local", at: start + Double(index))
        }
        #expect(log.entries.count == AutoAllowLog.capacity)
        #expect(log.entries.first?.subject == "site59.local")
        #expect(log.total == 60)
    }
}
