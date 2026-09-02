import Foundation

// MARK: - Adult content filter — EXACT port of src/lib/addons-store/adult-filter.ts
// (verified 2026-09-02 @0117755). Same term lists, same leet/diacritic normalization,
// same two-pass matching (substring first, then word-boundary tokens).

enum AdultContentFilter {

    static let substringTerms: [String] = [
        "porn", "pornhub", "pornography", "porno", "porntv", "xhamster", "xnxx",
        "xvideos", "redtube", "youporn", "spankbang", "brazzers", "naughtyamerica",
        "bangbros", "realitykings", "evilangel", "digitalplayground", "fakehub",
        "playboy", "penthouse", "hustler", "rule34", "rule35", "hentai", "ahegao",
        "doujin", "doujinshi", "ecchi", "futanari", "futa", "yiff", "lewd", "smut",
        "fapping", "milf", "gilf", "dilf", "shemale", "ladyboy", "tranny", "femdom",
        "dominatrix", "bondage", "bdsm", "fetish", "fetlife", "kink", "kinky",
        "raunchy", "vulgar", "obscene", "softcore", "hardcore", "uncensored",
        "explicit", "chaturbate", "myfreecams", "stripchat", "bongacams",
        "livejasmin", "camsoda", "flirt4free", "camgirl", "camgirls", "camboy",
        "camboys", "camshow", "camshows", "webcamshow", "webcamshows", "onlyfans",
        "fansly", "manyvids", "clips4sale", "iwantclips", "modelhub", "incall",
        "outcall", "blowjob", "handjob", "footjob", "cumshot", "creampie",
        "cumming", "ejaculation", "ejaculate", "stripper", "stripping",
        "striptease", "lapdance", "lustful", "horny", "javhd", "thicc", "boobs",
        "boobies", "titties", "nipples", "asshole", "buttplug", "dildo",
        "vibrator", "deepthroat", "gangbang", "threesome", "foursome", "orgy",
        "orgies", "rimjob", "scat", "watersports", "incest", "stepmom",
        "stepsis", "stepbro", "barelylegal", "teenporn", "milfporn", "amateurporn",
    ]

    static let wordTerms: [String] = [
        "xxx", "nsfw", "sex", "sexy", "sexual", "erotic", "erotica", "nude",
        "nudes", "nudity", "naked", "topless", "ass", "anal", "anus", "tit",
        "tits", "boob", "cum", "cums", "jizz", "fuck", "fucker", "fucking",
        "fucked", "pussy", "pussies", "vagina", "vulva", "clit", "clitoris",
        "dick", "cock", "cocks", "penis", "balls", "fap", "wank", "jerk",
        "jerkoff", "stroke", "edging", "milf", "horny", "kinky", "lewd", "smut",
        "jav", "escort", "escorts", "slut", "sluts", "whore", "whores", "bitch",
        "bitches",
    ]

    static let leetMap: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
        "@": "a", "$": "s", "!": "i",
    ]

    /// normalize(): NFKD → lowercase → strip combining marks → leet map → strip non-letters.
    static func normalize(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        let nfkd = s.decomposedStringWithCanonicalMapping.lowercased()
        let stripped = nfkd.unicodeScalars.filter { !(0x0300...0x036F).contains($0.value) }
        var mapped = String(String.UnicodeScalarView(stripped))
        for (from, to) in leetMap { mapped = mapped.replacingOccurrences(of: String(from), with: String(to)) }
        let out = mapped.unicodeScalars.filter { $0.value >= 97 && $0.value <= 122 }
        return String(String.UnicodeScalarView(out))
    }

    /// lowerTokens(): like normalize but keeps digits and turns them into spaces.
    static func lowerTokens(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        let nfkd = s.decomposedStringWithCanonicalMapping.lowercased()
        let stripped = nfkd.unicodeScalars.filter { !(0x0300...0x036F).contains($0.value) }
        var mapped = String(String.UnicodeScalarView(stripped))
        for (from, to) in leetMap { mapped = mapped.replacingOccurrences(of: String(from), with: String(to)) }
        let chars = mapped.unicodeScalars.map { (c: Unicode.Scalar) -> String in
            let v = c.value
            if (97...122).contains(v) || (48...57).contains(v) { return String(c) }
            return " "
        }
        let joined = chars.joined().split(separator: " ").joined(separator: " ")
        return " " + joined + " "
    }

    static func isAdultText(_ fields: String?...) -> Bool {
        let normalized = fields.map { normalize($0) }.joined(separator: " ")
        for term in substringTerms where normalized.contains(term) { return true }
        let tokens = fields.map { lowerTokens($0) }.joined()
        guard !tokens.isEmpty else { return false }
        for term in wordTerms where tokens.contains(" \(term) ") { return true }
        return false
    }

    static let adultAnimeGenres: Set<String> = ["hentai", "erotica"]

    static func isAdultAnime(name: String?, genres: [String]?) -> Bool {
        if let genres, genres.contains(where: { adultAnimeGenres.contains($0.lowercased()) }) {
            return true
        }
        return isAdultText(name)
    }

    static func isAdultAddon(id: String, name: String, behaviorHintsAdult: Bool?) -> Bool {
        if behaviorHintsAdult == true { return true }
        return isAdultText(id, name)
    }
}
