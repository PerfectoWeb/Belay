import Testing

@testable import BelayModules

@Suite("Module search")
struct ModuleSearchTests {
    private let fields = ["Screenshot Cleaner", "Moves old screenshots to the Trash."]

    @Test("An empty field shows everything")
    func emptyQuery() {
        #expect(ModuleSearch.matches("", in: fields))
        #expect(ModuleSearch.matches("   ", in: fields))
    }

    @Test("Case does not matter")
    func caseInsensitive() {
        #expect(ModuleSearch.matches("TRASH", in: fields))
    }

    @Test("Every word has to be found, in any order and any field")
    func allTerms() {
        #expect(ModuleSearch.matches("trash cleaner", in: fields))
        #expect(!ModuleSearch.matches("trash microphone", in: fields))
    }

    @Test("Accents do not matter")
    func diacritics() {
        #expect(ModuleSearch.matches("ecran", in: ["Captures d'écran"]))
    }

    @Test("Other scripts are searched as typed")
    func otherScripts() {
        #expect(ModuleSearch.matches("снимк", in: ["Уборка снимков экрана"]))
        #expect(ModuleSearch.matches("截图", in: ["截图清理"]))
    }
}
