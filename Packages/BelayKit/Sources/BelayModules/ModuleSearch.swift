import Foundation

/// What the search field in Settings ▸ Modules matches.
public enum ModuleSearch {
    /// Every word typed has to be found somewhere in the module's text, in any
    /// order. Case and accents are ignored, so "ecran" finds "écran".
    ///
    /// An empty query matches everything: a cleared field shows the whole list.
    public static func matches(_ query: String, in fields: [String]) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        return terms.allSatisfy { term in
            fields.contains {
                $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}
