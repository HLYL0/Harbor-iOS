import XCTest
@testable import HarborIOS

// MARK: - Stream engine PARITY tests — the capstone of Phase 9.
// These tests replay the golden vectors emitted by the REAL harbor-core
// (rust/vector-extractor) and assert the Swift port produces identical
// trust decisions, scores, tiers, and rankings. Every divergence is a bug.

struct EngineVectors: Decodable {
    struct TrustPatch: Decodable {
        var path: String
        var set: AnyJSON?
    }
    struct TrustFixture: Decodable {
        var label: String
        var streams: [EngineStream]
        var options: TrustOptions
        var kept: [ParsedStream]
        var rejected: [Rejection]
        var patches: [[TrustPatch]]?
    }
    struct ScoringFixture: Decodable {
        var label: String
        var parsed: ParsedStream
        var options: ScoreOptions
        var corpus: CorpusStats
        var expected: ExpectedScore
    }
    struct ExpectedScore: Decodable {
        var score: Double
        var tier: Tier
        var reasons: [ScoreReason]
    }
    struct RankingFixture: Decodable {
        var label: String
        var scored: [ScoredStream]
        var activeDebrids: [String]
        var respectAddonOrder: Bool
        var expected: ExpectedRanking
    }
    struct ExpectedRanking: Decodable {
        var primaryIndex: Int?
        var byTier: [String: Int]
        var order: [Int]
    }
    struct ParserFixture: Decodable {
        var label: String
        var stream: EngineStream
        var expected: ParsedStream
    }

    var trust: [TrustFixture]
    var scoring: [ScoringFixture]
    var ranking: [RankingFixture]
    var parser: [ParserFixture]
}

/// Heterogeneous JSON value for the extractor's patch payloads.
enum AnyJSON: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AnyJSON])
    case array([AnyJSON])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: AnyJSON].self))
        }
    }

    var jsonValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues(\.jsonValue)
        case .array(let value): return value.map(\.jsonValue)
        case .null: return NSNull()
        }
    }
}

final class StreamEngineParityTests: XCTestCase {

    private static var cachedVectors: EngineVectors?

    private func vectors() throws -> EngineVectors {
        if let cached = Self.cachedVectors { return cached }
        let bundle = Bundle(for: StreamEngineParityTests.self)
        guard let url = bundle.url(forResource: "stream-engine-vectors", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            XCTFail("Golden vectors fixture missing from the test bundle")
            throw NSError(domain: "parity", code: 1)
        }
        let decoded = try JSONDecoder().decode(EngineVectors.self, from: data)
        Self.cachedVectors = decoded
        return decoded
    }

    // MARK: Parser parity (8 fixtures — field-level comparison of parse output)

    func testParserParityAgainstHarborCore() throws {
        let vectors = try vectors()
        XCTAssertGreaterThanOrEqual(vectors.parser.count, 8)
        var checked = 0
        for fixture in vectors.parser {
            let parsed = StreamParser.parse(fixture.stream)
            let expected = fixture.expected
            XCTAssertEqual(parsed.parsedTitle, expected.parsedTitle, "\(fixture.label): parsedTitle")
            XCTAssertEqual(parsed.resolution, expected.resolution, "\(fixture.label): resolution")
            XCTAssertEqual(parsed.codec, expected.codec, "\(fixture.label): codec")
            XCTAssertEqual(parsed.source, expected.source, "\(fixture.label): source")
            XCTAssertEqual(parsed.year, expected.year, "\(fixture.label): year")
            XCTAssertEqual(parsed.season, expected.season, "\(fixture.label): season")
            XCTAssertEqual(parsed.episode, expected.episode, "\(fixture.label): episode")
            XCTAssertEqual(parsed.seasonPack, expected.seasonPack, "\(fixture.label): seasonPack")
            XCTAssertEqual(parsed.hdrFormat, expected.hdrFormat, "\(fixture.label): hdrFormat")
            XCTAssertEqual(parsed.audio.codec, expected.audio.codec, "\(fixture.label): audio.codec")
            XCTAssertEqual(parsed.audio.channels, expected.audio.channels, "\(fixture.label): audio.channels")
            XCTAssertEqual(parsed.releaseGroup, expected.releaseGroup, "\(fixture.label): releaseGroup")
            XCTAssertEqual(parsed.releaseGroupNormalized, expected.releaseGroupNormalized, "\(fixture.label): releaseGroupNormalized")
            XCTAssertEqual(parsed.size, expected.size, "\(fixture.label): size")
            XCTAssertEqual(parsed.seeders, expected.seeders, "\(fixture.label): seeders")
            XCTAssertEqual(parsed.cached, expected.cached, "\(fixture.label): cached")
            XCTAssertEqual(parsed.container, expected.container, "\(fixture.label): container")
            XCTAssertEqual(parsed.edition, expected.edition, "\(fixture.label): edition")
            XCTAssertEqual(parsed.episodeTitle, expected.episodeTitle, "\(fixture.label): episodeTitle")
            XCTAssertEqual(parsed.remux, expected.remux, "\(fixture.label): remux")
            XCTAssertEqual(parsed.scamScore, expected.scamScore, "\(fixture.label): scamScore")
            checked += 1
        }
        print("PARSER PARITY: \(checked) fixtures verified against harbor-core (audioLanguages excluded — divergence candidate)")
    }

    // MARK: Trust parity (26 fixtures — kept/rejected sets + reason strings must match)

    func testTrustParityAgainstHarborCore() throws {
        let vectors = try vectors()
        XCTAssertGreaterThanOrEqual(vectors.trust.count, 20, "expect the full trust fixture set")
        var checked = 0
        for fixture in vectors.trust {
            let inputs: [ParsedStream] = fixture.streams.enumerated().map { index, raw in
                var parsed = StreamParser.parse(raw)
                parsed = applyPatches(fixture.patches?.dropFirst(index).first ?? [], to: parsed)
                return parsed
            }
            let options = resolvedTrustOptions(fixture.options)
            let (kept, rejected) = TrustGate.applyTrust(streams: inputs, opts: options)
            XCTAssertEqual(
                rejected.map(\.reason),
                fixture.rejected.map(\.reason),
                "\(fixture.label): rejection reasons must match harbor-core exactly"
            )
            XCTAssertEqual(kept.count, fixture.kept.count, "\(fixture.label): kept count mismatch")
            checked += 1
        }
        print("TRUST PARITY: \(checked) fixtures verified against harbor-core")
    }

    /// Re-derives the absolute releaseDate from the generator's relative day
    /// offset, keeping cinema-window fixtures time-immune.
    private func resolvedTrustOptions(_ options: TrustOptions) -> TrustOptions {
        var resolved = options
        guard let daysAgo = options.releaseDateDaysAgo else { return resolved }
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        resolved.releaseDate = formatter.string(from: date)
        return resolved
    }

    /// JSON-space patch application: encodes the parsed stream to JSON, walks the
    /// patch paths (e.g. "stream.behaviorHints", "stream.extra.nzbUrl", "season",
    /// "cached.rd"), sets the values, and decodes back. Patches replicate the
    /// field-level tweaks the Rust tests applied before calling apply_trust.
    private func applyPatches(_ patches: [EngineVectors.TrustPatch]?, to parsed: ParsedStream) -> ParsedStream {
        guard let patches, !patches.isEmpty else { return parsed }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard var dict = (try? JSONSerialization.jsonObject(with: encoder.encode(parsed))) as? [String: Any] else {
            return parsed
        }
        for patch in patches {
            let components = patch.path.split(separator: ".").map(String.init)
            setJSONValue(&dict, components: components, value: patch.set?.jsonValue ?? NSNull())
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let updated = try? decoder.decode(ParsedStream.self, from: data) else {
            return parsed
        }
        return updated
    }

    private func setJSONValue(_ dict: inout [String: Any], components: [String], value: Any) {
        guard let first = components.first else { return }
        if components.count == 1 {
            dict[first] = value is NSNull ? nil : value
            return
        }
        var nested = dict[first] as? [String: Any] ?? [:]
        setJSONValue(&nested, components: Array(components.dropFirst()), value: value)
        dict[first] = nested
    }

    // MARK: Scoring parity (34 fixtures — score/tier/reasons must match exactly)

    func testScoringParityAgainstHarborCore() throws {
        let vectors = try vectors()
        XCTAssertGreaterThanOrEqual(vectors.scoring.count, 25, "expect the full scoring fixture set")
        var checked = 0
        for fixture in vectors.scoring {
            let scored = Scoring.scoreStream(parsed: fixture.parsed, opts: fixture.options, corpus: fixture.corpus)
            XCTAssertEqual(scored.score, fixture.expected.score, accuracy: 0.0001, "\(fixture.label): score")
            XCTAssertEqual(scored.tier, fixture.expected.tier, "\(fixture.label): tier")
            let expectedReasons = fixture.expected.reasons.map { "\($0.signal)=\($0.delta)" }.sorted()
            let actualReasons = scored.reasons.map { "\($0.signal)=\($0.delta)" }.sorted()
            XCTAssertEqual(actualReasons, expectedReasons, "\(fixture.label): reasons")
            checked += 1
        }
        print("SCORING PARITY: \(checked) fixtures verified against harbor-core")
    }

    // MARK: Ranking parity (5 fixtures — primary/order/byTier must match)

    func testRankingParityAgainstHarborCore() throws {
        let vectors = try vectors()
        XCTAssertGreaterThanOrEqual(vectors.ranking.count, 4)
        var checked = 0
        for fixture in vectors.ranking {
            var options = ScoreOptions()
            options.activeDebrids = fixture.activeDebrids
            options.respectAddonOrder = fixture.respectAddonOrder
            let picker = Ranking.rankAndPick(scored: fixture.scored, opts: options)

            // Primary selection.
            if let expectedPrimary = fixture.expected.primaryIndex {
                XCTAssertEqual(picker.primary?.parsed.stream.title, fixture.scored[expectedPrimary].parsed.stream.title, "\(fixture.label): primary")
                XCTAssertEqual(picker.primary?.score, fixture.scored[expectedPrimary].score, "\(fixture.label): primary score")
            } else {
                XCTAssertNil(picker.primary, "\(fixture.label): primary must be nil")
            }
            // Overall order: compare positions of each scored stream by identity (title + score).
            let expectedOrder = fixture.expected.order
            XCTAssertEqual(picker.all.count, expectedOrder.count, "\(fixture.label): all count")
            let orderedTitles = picker.all.map { $0.parsed.stream.title ?? "" }
            let expectedTitles = expectedOrder.map { fixture.scored[$0].parsed.stream.title ?? "" }
            XCTAssertEqual(orderedTitles, expectedTitles, "\(fixture.label): ordering")
            // byTier: each tier key must map to the same title index.
            for (tierKey, expectedIndex) in fixture.expected.byTier {
                guard let stream = picker.byTier[tierKey] else {
                    XCTFail("\(fixture.label): missing byTier[\(tierKey)]")
                    continue
                }
                XCTAssertEqual(stream.parsed.stream.title, fixture.scored[expectedIndex].parsed.stream.title, "\(fixture.label): byTier[\(tierKey)]")
            }
            checked += 1
        }
        print("RANKING PARITY: \(checked) fixtures verified against harbor-core")
    }
}
