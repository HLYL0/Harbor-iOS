//! Golden-vector extractor for the Harbor stream engine.
//!
//! Re-expresses every expressible `#[test]` scenario from
//! `rust/harbor-core/src/{parser,trust,scoring}.rs` as data, executes the REAL
//! harbor-core functions on those inputs, and emits one JSON document that the
//! Swift port (`Domain/StreamEngine/`) can decode and replay 1:1 for parity.
//!
//! IMPORTANT SHAPE NOTE: the Rust types serialize FLAT (`#[serde(flatten)]` on
//! `ParsedStream.stream` / `ScoredStream.parsed`), but `EngineModels.swift`
//! expects the NESTED shape (`{"stream": {...}, "parsedTitle": ...}` and
//! `{"parsed": {...}, "score": ...}`). This binary therefore builds the JSON
//! tree manually in the Swift-compatible shape instead of deriving Serialize.

use harbor_core::*;
use serde::de::DeserializeOwned;
use serde_json::{json, Value};

const OUT_PATH: &str =
    "C:/Users/Admin/Desktop/Harbor-iOS/Tests/Fixtures/stream-engine-vectors.json";

const GIB: u64 = 1024 * 1024 * 1024;
const MIB: u64 = 1024 * 1024;

// ---------------------------------------------------------------------------
// Time helpers (mirror the civil-date algorithm used by the Rust test modules)
// ---------------------------------------------------------------------------

fn now_ms() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("clock before epoch")
        .as_millis() as f64
}

fn civil_from_days(z: i64) -> (i32, u32, u32) {
    let z = z + 719_468;
    let era = (if z >= 0 { z } else { z - 146_096 }) / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = (if mp < 10 { mp + 3 } else { mp - 9 }) as u32;
    let y = y + if m <= 2 { 1 } else { 0 };
    (y as i32, m, d)
}

/// ISO date `days` days before *now* (same convention as the Rust tests).
fn days_ago_iso(days: f64) -> String {
    let ms = now_ms() - days * 86_400_000.0;
    let day_num = (ms / 86_400_000.0).floor() as i64;
    let (y, m, d) = civil_from_days(day_num);
    format!("{y:04}-{m:02}-{d:02}")
}

// ---------------------------------------------------------------------------
// Enum -> JSON raw-value stringifiers (serde renames, mirrored by Swift)
// ---------------------------------------------------------------------------

fn res_str(r: Resolution) -> &'static str {
    match r {
        Resolution::UHD => "4K",
        Resolution::P1080 => "1080p",
        Resolution::P720 => "720p",
        Resolution::P480 => "480p",
        Resolution::SD => "SD",
    }
}

fn hdr_str(h: HdrFormat) -> &'static str {
    match h {
        HdrFormat::Hdr10 => "HDR10",
        HdrFormat::Hdr10Plus => "HDR10+",
        HdrFormat::Dv => "DV",
        HdrFormat::DvHdr10 => "DV+HDR10",
        HdrFormat::Hlg => "HLG",
    }
}

fn codec_str(c: Codec) -> &'static str {
    match c {
        Codec::Hevc => "HEVC",
        Codec::Avc => "AVC",
        Codec::Av1 => "AV1",
        Codec::Vp9 => "VP9",
        Codec::Mpeg2 => "MPEG2",
        Codec::Other => "Other",
    }
}

fn audio_codec_str(a: AudioCodec) -> &'static str {
    match a {
        AudioCodec::Atmos => "Atmos",
        AudioCodec::TrueHd => "TrueHD",
        AudioCodec::DtsHdMa => "DTS-HD MA",
        AudioCodec::Dts => "DTS",
        AudioCodec::DdPlus => "DD+",
        AudioCodec::Ac3 => "AC3",
        AudioCodec::Aac => "AAC",
        AudioCodec::Opus => "Opus",
        AudioCodec::Flac => "FLAC",
        AudioCodec::Other => "Other",
    }
}

fn source_str(s: Source) -> &'static str {
    match s {
        Source::BluRay => "BluRay",
        Source::REMUX => "REMUX",
        Source::WebDl => "WEB-DL",
        Source::WEBRip => "WEBRip",
        Source::BDRip => "BDRip",
        Source::HDRip => "HDRip",
        Source::DVDRip => "DVDRip",
        Source::HDTV => "HDTV",
        Source::CAM => "CAM",
        Source::TS => "TS",
        Source::HDTS => "HDTS",
        Source::TC => "TC",
        Source::SCR => "SCR",
        Source::Other => "Other",
    }
}

fn tier_str(t: Tier) -> &'static str {
    match t {
        Tier::UhdDv => "4K_DV",
        Tier::UhdHdr => "4K_HDR",
        Tier::Uhd => "4K",
        Tier::P1080Hdr => "1080p_HDR",
        Tier::P1080 => "1080p",
        Tier::P720 => "720p",
        Tier::SD => "SD",
        Tier::Rough => "ROUGH",
    }
}

fn container_str(c: Container) -> &'static str {
    match c {
        Container::Mkv => "mkv",
        Container::Mp4 => "mp4",
        Container::M4v => "m4v",
        Container::Avi => "avi",
        Container::Webm => "webm",
        Container::Mov => "mov",
        Container::Ts => "ts",
        Container::Wmv => "wmv",
    }
}

// ---------------------------------------------------------------------------
// Swift-shaped serializers
// ---------------------------------------------------------------------------

/// `EngineStream` JSON. The Rust `Stream` derives already match the Swift
/// `EngineStream` Codable shape (camelCase, optionals skipped); the flattened
/// `extra` map lands as top-level unknown keys that Swift ignores.
fn stream_json(s: &Stream) -> Value {
    serde_json::to_value(s).expect("serialize Stream")
}

/// `ParsedStream` JSON in the Swift NESTED shape (`stream` sub-object).
fn parsed_swift(p: &ParsedStream) -> Value {
    // json! takes field expressions by value; clone once so the moves are legal.
    let p = p.clone();
    json!({
        "stream": stream_json(&p.stream),
        "parsedTitle": p.parsed_title,
        "episodeTitle": p.episode_title,
        "resolution": res_str(p.resolution),
        "hdrFormat": p.hdr_format.map(hdr_str),
        "codec": codec_str(p.codec),
        "source": source_str(p.source),
        "audio": {
            "codec": audio_codec_str(p.audio.codec),
            "channels": p.audio.channels,
            "bitDepth": p.audio.bit_depth,
        },
        "audioLanguages": p.audio_languages,
        "size": p.size,
        "seeders": p.seeders,
        "cached": p.cached,
        "inLibrary": p.in_library,
        "container": p.container.map(container_str),
        "releaseGroup": p.release_group,
        "releaseGroupNormalized": p.release_group_normalized,
        "remux": p.remux,
        "edition": p.edition,
        "year": p.year,
        "yearRange": p.year_range.map(|(a, b)| json!([a, b])),
        "season": p.season,
        "episode": p.episode,
        "seasonPack": p.season_pack,
        "discIndex": p.disc_index,
        "repackIteration": p.repack_iteration,
        "proper": p.proper,
        "hardcoded": p.hardcoded,
        "animeHash": p.anime_hash,
        "scamScore": p.scam_score,
    })
}

/// `ScoredStream` JSON in the Swift NESTED shape (`parsed` sub-object).
fn scored_swift(s: &ScoredStream) -> Value {
    json!({
        "parsed": parsed_swift(&s.parsed),
        "score": s.score,
        "reasons": s.reasons
            .iter()
            .map(|r| json!({ "signal": r.signal, "delta": r.delta }))
            .collect::<Vec<_>>(),
        "tier": tier_str(s.tier),
    })
}

fn corpus_input_json(c: &scoring::CorpusStats) -> Value {
    json!({
        "daysSinceRelease": c.days_since_release,
        "trustedTrackedFraction": c.trusted_tracked_fraction,
        "theaterCaptureFraction": c.theater_capture_fraction,
        "webishFraction": c.webish_fraction,
        "trustedTrackedCount": c.trusted_tracked_count,
    })
}

// ---------------------------------------------------------------------------
// Post-parse patch interpreter. Trust tests mutate a hand-built `ParsedStream`
// after construction; fixtures record those mutations as `{path, set}` pairs
// (camelCase paths over the Swift-shaped `ParsedStream`) so the Swift side can
// replay them after its own parse step.
// ---------------------------------------------------------------------------

fn option_from<T: DeserializeOwned>(v: &Value) -> Option<T> {
    if v.is_null() {
        None
    } else {
        Some(serde_json::from_value(v.clone()).expect("patch value"))
    }
}

fn apply_patch(p: &mut ParsedStream, path: &str, v: &Value) {
    let parts: Vec<&str> = path.split('.').collect();
    match parts.as_slice() {
        ["size"] => p.size = option_from::<u64>(v),
        ["seeders"] => p.seeders = option_from::<u32>(v),
        ["scamScore"] => p.scam_score = v.as_i64().unwrap_or(0) as i32,
        ["parsedTitle"] => p.parsed_title = v.as_str().unwrap_or("").to_string(),
        ["year"] => p.year = option_from::<u16>(v),
        ["season"] => p.season = option_from::<i32>(v),
        ["episode"] => p.episode = option_from::<i32>(v),
        ["seasonPack"] => p.season_pack = v.as_bool().unwrap_or(false),
        ["source"] => p.source = serde_json::from_value(v.clone()).expect("source patch"),
        ["resolution"] => p.resolution = serde_json::from_value(v.clone()).expect("resolution patch"),
        ["codec"] => p.codec = serde_json::from_value(v.clone()).expect("codec patch"),
        ["hdrFormat"] => p.hdr_format = option_from::<HdrFormat>(v),
        ["container"] => p.container = option_from::<Container>(v),
        ["remux"] => p.remux = v.as_bool().unwrap_or(false),
        ["proper"] => p.proper = v.as_bool().unwrap_or(false),
        ["hardcoded"] => p.hardcoded = v.as_bool().unwrap_or(false),
        ["repackIteration"] => p.repack_iteration = v.as_i64().unwrap_or(0) as i32,
        ["releaseGroup"] => p.release_group = option_from::<String>(v),
        ["releaseGroupNormalized"] => p.release_group_normalized = option_from::<String>(v),
        ["cached", slug] => {
            p.cached.insert((*slug).to_string(), v.as_bool().unwrap_or(false));
        }
        ["inLibrary", slug] => {
            p.in_library.insert((*slug).to_string(), v.as_bool().unwrap_or(false));
        }
        ["stream", "infoHash"] => p.stream.info_hash = option_from::<String>(v),
        ["stream", "url"] => p.stream.url = option_from::<String>(v),
        ["stream", "ytId"] => p.stream.yt_id = option_from::<String>(v),
        ["stream", "externalUrl"] => p.stream.external_url = option_from::<String>(v),
        ["stream", "fileIdx"] => p.stream.file_idx = option_from::<i64>(v),
        ["stream", "description"] => p.stream.description = option_from::<String>(v),
        ["stream", "name"] => p.stream.name = option_from::<String>(v),
        ["stream", "title"] => p.stream.title = option_from::<String>(v),
        ["stream", "addonName"] => p.stream.addon_name = v.as_str().unwrap_or("").to_string(),
        ["stream", "addonPriority"] => p.stream.addon_priority = option_from::<u32>(v),
        ["stream", "addonReturnIdx"] => p.stream.addon_return_idx = option_from::<u32>(v),
        ["stream", "behaviorHints"] => {
            p.stream.behavior_hints = if v.is_null() { None } else { Some(v.clone()) };
        }
        ["stream", "extra", key] => {
            if v.is_null() {
                p.stream.extra.remove(*key);
            } else {
                p.stream.extra.insert((*key).to_string(), v.clone());
            }
        }
        _ => panic!("unsupported patch path: {path}"),
    }
}

fn patch(path: &str, set: Value) -> Value {
    json!({ "path": path, "set": set })
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

fn parser_fixture(label: &str, raw: Value, asserts: &[&str]) -> Value {
    let s: Stream = serde_json::from_value(raw.clone()).expect("parse raw Stream");
    let p = parser::parse_stream(s);
    json!({
        "label": label,
        "stream": raw,
        "asserts": asserts,
        "expected": parsed_swift(&p),
    })
}

fn trust_fixture(
    label: &str,
    raws: &[Value],
    patches: &[Vec<Value>],
    opts: &TrustOptions,
    release_date_days_ago: Option<f64>,
) -> Value {
    let mut parsed: Vec<ParsedStream> = Vec::with_capacity(raws.len());
    for (i, raw) in raws.iter().enumerate() {
        let s: Stream = serde_json::from_value(raw.clone()).expect("parse raw Stream");
        let mut p = parser::parse_stream(s);
        if let Some(per_stream) = patches.get(i) {
            for pv in per_stream {
                let path = pv["path"].as_str().expect("patch path");
                apply_patch(&mut p, path, &pv["set"]);
            }
        }
        parsed.push(p);
    }
    let result = trust::apply_trust(parsed, opts);
    let mut opts_json = serde_json::to_value(opts).expect("serialize TrustOptions");
    if let Some(d) = release_date_days_ago {
        opts_json["releaseDateDaysAgo"] = json!(d);
    }
    json!({
        "label": label,
        "streams": raws,
        "patches": patches,
        "options": opts_json,
        "kept": result.keep.iter().map(parsed_swift).collect::<Vec<_>>(),
        "rejected": result
            .rejected
            .iter()
            .map(|r| json!({ "stream": parsed_swift(&r.stream), "reason": r.reason }))
            .collect::<Vec<_>>(),
    })
}

fn scoring_fixture(
    label: &str,
    parsed: ParsedStream,
    opts: &ScoreOptions,
    corpus: &scoring::CorpusStats,
    release_date_days_ago: Option<f64>,
) -> Value {
    let scored = scoring::score_stream(parsed.clone(), opts, corpus);
    let mut opts_json = serde_json::to_value(opts).expect("serialize ScoreOptions");
    if let Some(d) = release_date_days_ago {
        opts_json["releaseDateDaysAgo"] = json!(d);
    }
    json!({
        "label": label,
        "parsed": parsed_swift(&parsed),
        "options": opts_json,
        "corpus": corpus_input_json(corpus),
        "expected": {
            "score": scored.score,
            "tier": tier_str(scored.tier),
            "reasons": scored
                .reasons
                .iter()
                .map(|r| json!({ "signal": r.signal, "delta": r.delta }))
                .collect::<Vec<_>>(),
        },
    })
}

fn corpus_fixture(label: &str, parsed: &[ParsedStream], opts: &ScoreOptions) -> Value {
    let cs = scoring::compute_corpus_stats(parsed, opts);
    json!({
        "label": label,
        "parsed": parsed.iter().map(parsed_swift).collect::<Vec<_>>(),
        "options": serde_json::to_value(opts).expect("serialize ScoreOptions"),
        "expected": {
            "daysSinceRelease": cs.days_since_release,
            "trustedTrackedFraction": cs.trusted_tracked_fraction,
            "theaterCaptureFraction": cs.theater_capture_fraction,
            "webishFraction": cs.webish_fraction,
            "trustedTrackedCount": cs.trusted_tracked_count,
            // Rust-only percentile extensions; Swift `CorpusStats` ignores
            // unknown keys — decode with a wider model to assert these.
            "medianSize": cs.median_size,
            "p90Size": cs.p90_size,
            "p10Seeders": cs.p10_seeders,
            "p90Seeders": cs.p90_seeders,
        },
    })
}

fn ranking_fixture(
    label: &str,
    scored: Vec<ScoredStream>,
    active_debrids: &[String],
    respect_addon_order: bool,
) -> Value {
    let picker = scoring::rank_and_pick(scored.clone(), active_debrids, respect_addon_order);
    let inputs: Vec<Value> = scored.iter().map(scored_swift).collect();
    let idx_of = |v: &Value| -> Option<i64> {
        inputs.iter().position(|x| x == v).map(|i| i as i64)
    };
    let by_tier: std::collections::BTreeMap<String, Option<i64>> = picker
        .by_tier
        .iter()
        .map(|(k, v)| (k.clone(), idx_of(&scored_swift(v))))
        .collect();
    json!({
        "label": label,
        "scored": inputs,
        "activeDebrids": active_debrids,
        "respectAddonOrder": respect_addon_order,
        "expected": {
            "primaryIndex": picker.primary.as_ref().and_then(|p| idx_of(&scored_swift(p))),
            "byTier": by_tier,
            "order": picker
                .all
                .iter()
                .map(|v| idx_of(&scored_swift(v)))
                .collect::<Vec<_>>(),
        },
    })
}

// ---------------------------------------------------------------------------
// Scenario data (mirrors of the Rust #[test] modules)
// ---------------------------------------------------------------------------

const HASH40: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

/// Raw `Stream` for the trust tests' `base_stream()` — the parser derives the
/// same resolution/codec/source/year/size/seeders/container values the tests
/// hard-code (1080p / HEVC / WEB-DL / 2020 / 2 GiB / 50 seeders / mkv).
fn trust_base_raw() -> Value {
    json!({
        "title": "Sample.Movie.2020.1080p.WEB-DL.x265.mkv\n👤 50 💾 2 GB",
        "infoHash": HASH40,
        "addonId": "addon",
        "addonName": "Addon",
    })
}

fn opts_strict() -> TrustOptions {
    TrustOptions {
        strict: true,
        ..Default::default()
    }
}

/// `base_parsed()` mirror from the scoring test module.
fn base_scoring() -> ParsedStream {
    ParsedStream {
        stream: Stream {
            addon_id: "test".to_string(),
            addon_name: "test-addon".to_string(),
            ..Default::default()
        },
        parsed_title: String::new(),
        episode_title: None,
        resolution: Resolution::P1080,
        hdr_format: None,
        codec: Codec::Other,
        source: Source::WebDl,
        audio: AudioInfo::default(),
        audio_languages: Vec::new(),
        size: None,
        seeders: None,
        cached: Default::default(),
        in_library: Default::default(),
        container: None,
        release_group: None,
        release_group_normalized: None,
        remux: false,
        edition: None,
        year: None,
        year_range: None,
        season: None,
        episode: None,
        season_pack: false,
        disc_index: None,
        repack_iteration: 0,
        proper: false,
        hardcoded: false,
        anime_hash: None,
        scam_score: 0,
    }
}

fn empty_opts() -> ScoreOptions {
    ScoreOptions::default()
}

fn empty_corpus() -> scoring::CorpusStats {
    scoring::CorpusStats::default()
}

fn main() {
    let mut parser_fixtures: Vec<Value> = Vec::new();
    let mut trust_fixtures: Vec<Value> = Vec::new();
    let mut scoring_fixtures: Vec<Value> = Vec::new();
    let mut corpus_fixtures: Vec<Value> = Vec::new();
    let mut ranking_fixtures: Vec<Value> = Vec::new();

    // ======================================================================
    // PARSER — 8 scenarios (parser.rs:1666-1778)
    // ======================================================================

    parser_fixtures.push(parser_fixture(
        "parser/parses_torrentio_1080p_webdl",
        json!({
            "title": "The.Matrix.1999.1080p.WEB-DL.DDP5.1.H.264-FLUX\n👤 25 💾 2.5 GB ⚡ Real-Debrid",
            "addonId": "test",
            "addonName": "Torrentio",
        }),
        &[
            "resolution == 1080p",
            "codec == AVC",
            "source == WEB-DL",
            "year == 1999",
            "audio.codec == DD+ && audio.channels == 6",
            "releaseGroup == FLUX && releaseGroupNormalized == FLUX",
            "size > 2_000_000_000",
            "seeders == 25",
            "cached[rd] == true",
        ],
    ));

    parser_fixtures.push(parser_fixture(
        "parser/parses_yts_1080p_x265",
        json!({
            "title": "The.Dark.Knight.2008.1080p.BluRay.x265-YTS",
            "addonId": "test",
            "addonName": "YTS",
        }),
        &["resolution == 1080p", "codec == HEVC", "source == BluRay", "year == 2008"],
    ));

    parser_fixtures.push(parser_fixture(
        "parser/parses_cam_release_lowest_quality",
        json!({
            "title": "Some.Movie.2024.HDCAM.x264-NEW\n💾 1.2 GB",
            "addonId": "test",
            "addonName": "Torrentio",
        }),
        &["source == CAM", "year == 2024"],
    ));

    parser_fixtures.push(parser_fixture(
        "parser/parses_4k_dv_hdr10",
        json!({
            "title": "Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR10.HEVC.TrueHD.7.1.Atmos-FraMeSToR\n💾 80.5 GB",
            "addonId": "test",
            "addonName": "Torrentio",
        }),
        &[
            "resolution == 4K",
            "codec == HEVC",
            "source == REMUX",
            "hdrFormat == DV+HDR10",
            "remux == true",
            "audio.codec == Atmos && audio.channels == 8",
            "year == 2024",
            "releaseGroup == FraMeSToR && releaseGroupNormalized == FRAMESTOR (trusted)",
        ],
    ));

    parser_fixtures.push(parser_fixture(
        "parser/detects_season_pack",
        json!({
            "title": "Breaking.Bad.S01.Complete.1080p.BluRay.x264-DEMAND",
            "addonId": "test",
            "addonName": "Torrentio",
        }),
        &[
            "season == 1",
            "episode == nil",
            "seasonPack == true",
            "resolution == 1080p",
        ],
    ));

    parser_fixtures.push(parser_fixture(
        "parser/detects_episode_with_title",
        json!({
            "title": "The.Office.S03E10.A.Benihana.Christmas.720p.WEB-DL.x264.mkv",
            "addonId": "test",
            "addonName": "Torrentio",
        }),
        &[
            "season == 3 && episode == 10",
            "resolution == 720p",
            "episodeTitle lowercased contains 'benihana'",
            "container == mkv",
        ],
    ));

    parser_fixtures.push(parser_fixture(
        "parser/empty_stream_falls_back_to_defaults",
        json!({ "addonId": "x", "addonName": "x" }),
        &["resolution == SD", "codec == Other", "source == Other"],
    ));

    parser_fixtures.push(parser_fixture(
        "parser/behavior_hints_video_size_used",
        json!({
            "title": "Movie.2020.1080p.WEB-DL.x264",
            "behaviorHints": { "videoSize": 5_000_000_000_u64 },
            "addonId": "test",
            "addonName": "Torrentio",
        }),
        &["size == 5_000_000_000"],
    ));

    // ======================================================================
    // TRUST — 26 scenarios (trust.rs:713-1019); one private-helper test
    // (tokenize) is not expressible through the public API — see "skipped".
    // ======================================================================

    let no_patches: Vec<Vec<Value>> = vec![vec![]];

    trust_fixtures.push(trust_fixture(
        "trust/keeps_clean_stream",
        &[trust_base_raw()],
        &no_patches,
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_suspicious_extension",
        &[trust_base_raw()],
        &[vec![patch("stream.behaviorHints", json!({ "filename": "Setup.exe" }))]],
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/allows_season_pack_when_flag_set",
        &[trust_base_raw()],
        &[vec![patch("season", json!(1)), patch("seasonPack", json!(true))]],
        &TrustOptions {
            allow_season_packs: true,
            expected_season: Some(1),
            expected_episode: Some(3),
            ..opts_strict()
        },
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_trailer_below_ceiling",
        &[trust_base_raw()],
        &[vec![
            patch("stream.behaviorHints", json!({ "filename": "movie.trailer.mkv" })),
            patch("size", json!(50 * MIB)),
        ]],
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_no_playable_source",
        &[trust_base_raw()],
        &[vec![patch("stream.infoHash", Value::Null)]],
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/keeps_nzb_only_stream",
        &[trust_base_raw()],
        &[vec![
            patch("stream.infoHash", Value::Null),
            patch("stream.extra.nzbUrl", json!("https://x/nzb")),
        ]],
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_size_stub",
        &[trust_base_raw()],
        &[vec![patch("size", json!(MIB))]],
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_scam_score",
        &[trust_base_raw()],
        &[vec![patch("scamScore", json!(7))]],
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/disabled_short_circuits",
        &[trust_base_raw(), trust_base_raw()],
        &[
            vec![],
            vec![patch("size", json!(500 * GIB))],
        ],
        &TrustOptions {
            disabled: true,
            expected_year: Some(1900),
            ..opts_strict()
        },
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_series_result_for_movie",
        &[trust_base_raw()],
        &[vec![
            patch("parsedTitle", json!("Obsession")),
            patch("season", json!(1)),
            patch("episode", json!(1)),
        ]],
        &TrustOptions {
            kind: Some("movie".into()),
            ..opts_strict()
        },
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_season_pack_for_movie",
        &[trust_base_raw()],
        &[vec![
            patch("parsedTitle", json!("Obsession")),
            patch("seasonPack", json!(true)),
            patch("season", json!(1)),
        ]],
        &TrustOptions {
            kind: Some("movie".into()),
            ..opts_strict()
        },
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_cinema_bare_untagged",
        &[trust_base_raw()],
        &[vec![
            patch("parsedTitle", json!("Obsession")),
            patch("year", Value::Null),
            patch("source", json!("Other")),
            patch("resolution", json!("SD")),
        ]],
        &TrustOptions {
            kind: Some("movie".into()),
            expected_year: Some(2025),
            release_date: Some(days_ago_iso(7.0)),
            ..opts_strict()
        },
        Some(7.0),
    ));

    trust_fixtures.push(trust_fixture(
        "trust/keeps_real_movie_in_cinema_window",
        &[trust_base_raw()],
        &[vec![
            patch("parsedTitle", json!("Obsession")),
            patch("year", json!(2025)),
            patch("source", json!("WEB-DL")),
            patch("resolution", json!("1080p")),
        ]],
        &TrustOptions {
            kind: Some("movie".into()),
            expected_year: Some(2025),
            release_date: Some(days_ago_iso(7.0)),
            ..opts_strict()
        },
        Some(7.0),
    ));

    trust_fixtures.push(trust_fixture(
        "trust/season_pack_with_file_idx_skips_episode_check",
        &[trust_base_raw()],
        &[vec![
            patch("stream.fileIdx", json!(2)),
            patch("episode", json!(7)),
        ]],
        &TrustOptions {
            expected_episode: Some(3),
            ..opts_strict()
        },
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_placeholder_banner",
        &[trust_base_raw()],
        &[vec![patch("stream.description", json!("🚫 No streams found"))]],
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_status_card",
        &[trust_base_raw()],
        &[vec![
            patch("stream.infoHash", Value::Null),
            patch("stream.url", json!("https://example.com/account")),
            patch("stream.description", json!("Premium expires in 3 days")),
        ]],
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_uncached_emoji",
        &[trust_base_raw()],
        &[vec![patch("stream.name", json!("⏳ Cloud only"))]],
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_underscore_delimited_trailer",
        &[trust_base_raw()],
        &[vec![patch(
            "stream.behaviorHints",
            json!({ "filename": "Movie_2025_trailer_1080p.mkv" }),
        )]],
        &opts_strict(),
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_cinema_year_mismatch",
        &[trust_base_raw()],
        &[vec![
            patch("parsedTitle", json!("The Strangers")),
            patch("year", json!(2008)),
            patch("resolution", json!("720p")),
            patch("source", json!("WEB-DL")),
        ]],
        &TrustOptions {
            kind: Some("movie".into()),
            expected_year: Some(2025),
            release_date: Some(days_ago_iso(7.0)),
            ..opts_strict()
        },
        Some(7.0),
    ));

    trust_fixtures.push(trust_fixture(
        "trust/rejects_fresh_cinema_fake_hdtv",
        &[trust_base_raw()],
        &[vec![
            patch("parsedTitle", json!("New Movie")),
            patch("year", json!(2025)),
            patch("source", json!("HDTV")),
            patch("resolution", json!("1080p")),
        ]],
        &TrustOptions {
            kind: Some("movie".into()),
            expected_year: Some(2025),
            release_date: Some(days_ago_iso(7.0)),
            ..opts_strict()
        },
        Some(7.0),
    ));

    trust_fixtures.push(trust_fixture(
        "trust/anime_keeps_small_episode_non_anime_rejects:non_anime",
        &[trust_base_raw()],
        &[vec![patch("size", json!(180 * MIB))]],
        &TrustOptions {
            kind: Some("series".into()),
            ..opts_strict()
        },
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/anime_keeps_small_episode_non_anime_rejects:anime",
        &[trust_base_raw()],
        &[vec![patch("size", json!(180 * MIB))]],
        &TrustOptions {
            kind: Some("series".into()),
            is_anime: true,
            ..opts_strict()
        },
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/short_format_exempts_small_episode",
        &[trust_base_raw()],
        &[vec![
            patch("stream.behaviorHints", json!({ "filename": "Show.OVA.1080p.mkv" })),
            patch("size", json!(80 * MIB)),
        ]],
        &TrustOptions {
            kind: Some("series".into()),
            ..opts_strict()
        },
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/title_short_guard_rejects_keyword_in_long_title",
        &[trust_base_raw()],
        &[vec![
            patch("parsedTitle", json!("DBM Obsession Viva Las Vegas")),
            patch("year", json!(2025)),
        ]],
        &TrustOptions {
            kind: Some("movie".into()),
            expected_title: Some("Obsession".into()),
            expected_year: Some(2025),
            ..opts_strict()
        },
        None,
    ));

    // Re-expression of the private `title_matches("Rocky","Rocky II",1979,1976)`
    // helper test: apply_trust's title gate calls title_matches(expected,
    // parsedTitle, parsed.year, opts.expectedYear), so expectedTitle="Rocky",
    // expectedYear=1976, stream year=1979 reproduces the exact call.
    trust_fixtures.push(trust_fixture(
        "trust/title_year_tolerance_scales_with_age",
        &[trust_base_raw()],
        &[vec![
            patch("parsedTitle", json!("Rocky II")),
            patch("year", json!(1979)),
        ]],
        &TrustOptions {
            kind: Some("movie".into()),
            expected_title: Some("Rocky".into()),
            expected_year: Some(1976),
            ..opts_strict()
        },
        None,
    ));

    trust_fixtures.push(trust_fixture(
        "trust/status_card_camelcase_filename_not_exempted",
        &[trust_base_raw()],
        &[vec![
            patch("stream.infoHash", Value::Null),
            patch("stream.url", json!("https://example.com/acct")),
            patch("stream.description", json!("Premium expires in 3 days")),
            patch("stream.behaviorHints", json!({ "fileName": "card.mkv" })),
        ]],
        &opts_strict(),
        None,
    ));

    // ======================================================================
    // SCORING — 22 scenarios (scoring.rs:1377-1869); sub-case assertions are
    // expanded into one fixture per assertion target.
    // ======================================================================

    // fresh_theater_window_protects_dominated_pool_past_30_days (2 sub-cases)
    let dominated = scoring::CorpusStats {
        days_since_release: Some(50.0),
        theater_capture_fraction: 0.8,
        webish_fraction: 0.1,
        trusted_tracked_count: 10,
        ..Default::default()
    };
    let fresh_opts = ScoreOptions {
        media_kind: Some("movie".to_string()),
        release_date: Some(days_ago_iso(50.0)),
        ..Default::default()
    };

    let mut fresh_ts = base_scoring();
    fresh_ts.source = Source::TS;
    scoring_fixtures.push(scoring_fixture(
        "scoring/fresh_theater_window_protects_dominated_pool_past_30_days:ts_boosted",
        fresh_ts,
        &fresh_opts,
        &dominated,
        Some(50.0),
    ));

    let mut fresh_web = base_scoring();
    fresh_web.source = Source::WEBRip;
    fresh_web.resolution = Resolution::UHD;
    scoring_fixtures.push(scoring_fixture(
        "scoring/fresh_theater_window_protects_dominated_pool_past_30_days:webrip_penalized",
        fresh_web.clone(),
        &fresh_opts,
        &dominated,
        Some(50.0),
    ));

    // fresh_non_dominated_still_skips_after_30_days
    let non_dominated = scoring::CorpusStats {
        days_since_release: Some(50.0),
        theater_capture_fraction: 0.1,
        webish_fraction: 0.7,
        trusted_tracked_count: 10,
        ..Default::default()
    };
    scoring_fixtures.push(scoring_fixture(
        "scoring/fresh_non_dominated_still_skips_after_30_days",
        fresh_web,
        &fresh_opts,
        &non_dominated,
        Some(50.0),
    ));

    // scoring_4k_hdr_with_atmos_and_hevc
    let mut p = base_scoring();
    p.resolution = Resolution::UHD;
    p.hdr_format = Some(HdrFormat::Hdr10);
    p.codec = Codec::Hevc;
    p.audio = AudioInfo {
        codec: AudioCodec::Atmos,
        channels: 8,
        bit_depth: None,
    };
    p.source = Source::WebDl;
    scoring_fixtures.push(scoring_fixture(
        "scoring/scoring_4k_hdr_with_atmos_and_hevc",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // scoring_4k_dv_uses_dv_tier_and_higher_hdr_delta
    let mut p = base_scoring();
    p.resolution = Resolution::UHD;
    p.hdr_format = Some(HdrFormat::DvHdr10);
    scoring_fixtures.push(scoring_fixture(
        "scoring/scoring_4k_dv_uses_dv_tier_and_higher_hdr_delta",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // scoring_cached_debrid_and_strong_addon
    let mut p = base_scoring();
    p.stream.addon_name = "MediaFusion".to_string();
    p.cached.insert("rd".to_string(), true);
    scoring_fixtures.push(scoring_fixture(
        "scoring/scoring_cached_debrid_and_strong_addon",
        p,
        &ScoreOptions {
            active_debrids: vec!["rd".to_string()],
            ..Default::default()
        },
        &empty_corpus(),
        None,
    ));

    // scoring_easynews_addon_treated_as_cached_alternative
    let mut p = base_scoring();
    p.stream.addon_name = "Easynews+".to_string();
    scoring_fixtures.push(scoring_fixture(
        "scoring/scoring_easynews_addon_treated_as_cached_alternative",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // scoring_cam_source_penalized_and_marked_rough
    let mut p = base_scoring();
    p.source = Source::CAM;
    p.resolution = Resolution::P720;
    scoring_fixtures.push(scoring_fixture(
        "scoring/scoring_cam_source_penalized_and_marked_rough",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // scoring_seeders_below_10_no_boost_unless_zero_with_hash (4 sub-cases)
    let mut p = base_scoring();
    p.seeders = Some(5);
    p.stream.info_hash = Some("abc".to_string());
    scoring_fixtures.push(scoring_fixture(
        "scoring/seeders:5_no_boost",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.seeders = Some(0);
    p.stream.info_hash = Some("abc".to_string());
    scoring_fixtures.push(scoring_fixture(
        "scoring/seeders:0_with_hash",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.seeders = Some(95);
    scoring_fixtures.push(scoring_fixture(
        "scoring/seeders:95",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.seeders = Some(500);
    scoring_fixtures.push(scoring_fixture(
        "scoring/seeders:500_capped",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // scoring_preferred_language_match_and_mismatch (4 sub-cases)
    let pref_en = ScoreOptions {
        preferred_languages: vec!["en".to_string()],
        ..Default::default()
    };
    let mut p = base_scoring();
    p.audio_languages = vec!["English".to_string()];
    scoring_fixtures.push(scoring_fixture(
        "scoring/preferred_language:english_match",
        p,
        &pref_en,
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.audio_languages = vec!["French".to_string()];
    scoring_fixtures.push(scoring_fixture(
        "scoring/preferred_language:french_mismatch",
        p,
        &pref_en,
        &empty_corpus(),
        None,
    ));

    let p = base_scoring();
    scoring_fixtures.push(scoring_fixture(
        "scoring/preferred_language:empty_unknown",
        p,
        &pref_en,
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.audio_languages = vec!["Multi".to_string()];
    scoring_fixtures.push(scoring_fixture(
        "scoring/preferred_language:multi",
        p,
        &pref_en,
        &empty_corpus(),
        None,
    ));

    // tier_assignment_edge_cases (9 sub-cases)
    let mut p = base_scoring();
    p.resolution = Resolution::UHD;
    p.hdr_format = Some(HdrFormat::Dv);
    scoring_fixtures.push(scoring_fixture(
        "scoring/tier_edge:uhd_dv",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.resolution = Resolution::UHD;
    p.hdr_format = Some(HdrFormat::Hdr10);
    scoring_fixtures.push(scoring_fixture(
        "scoring/tier_edge:uhd_hdr10",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.resolution = Resolution::UHD;
    scoring_fixtures.push(scoring_fixture(
        "scoring/tier_edge:uhd",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let p = base_scoring();
    scoring_fixtures.push(scoring_fixture(
        "scoring/tier_edge:1080p",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.hdr_format = Some(HdrFormat::Hlg);
    scoring_fixtures.push(scoring_fixture(
        "scoring/tier_edge:1080p_hlg",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.resolution = Resolution::P720;
    scoring_fixtures.push(scoring_fixture(
        "scoring/tier_edge:720p",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.resolution = Resolution::P480;
    scoring_fixtures.push(scoring_fixture(
        "scoring/tier_edge:480p_sd",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // tier_assignment_edge_cases — note the Rust test mutates ONE stream in
    // sequence; the SCR sub-case runs at P480 (left over from the SD case).
    let mut p = base_scoring();
    p.resolution = Resolution::P480;
    p.source = Source::SCR;
    scoring_fixtures.push(scoring_fixture(
        "scoring/tier_edge:scr_rough",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.source = Source::CAM;
    p.resolution = Resolution::UHD;
    p.hdr_format = Some(HdrFormat::Dv);
    scoring_fixtures.push(scoring_fixture(
        "scoring/tier_edge:cam_4k_dv_rough",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // proper_repack_iteration_logic (3 sub-cases)
    let mut p = base_scoring();
    p.proper = true;
    scoring_fixtures.push(scoring_fixture(
        "scoring/proper_repack:proper",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.repack_iteration = 1;
    scoring_fixtures.push(scoring_fixture(
        "scoring/proper_repack:repack1",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.repack_iteration = 5;
    scoring_fixtures.push(scoring_fixture(
        "scoring/proper_repack:repack5",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // trusted_release_group_and_remux_bonuses
    let mut p = base_scoring();
    p.release_group_normalized = Some("FLUX".to_string());
    p.remux = true;
    p.source = Source::BluRay;
    scoring_fixtures.push(scoring_fixture(
        "scoring/trusted_release_group_and_remux_bonuses",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // cam_in_filename_penalty_for_1080p_word
    let mut p = base_scoring();
    p.stream.title = Some("Some.Movie.1080p.WEB-DL.HDCAM.mkv".to_string());
    scoring_fixtures.push(scoring_fixture(
        "scoring/cam_in_filename_penalty_for_1080p_word",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // scoring_addon_priority_bonus_decays_with_position (4 sub-cases)
    let mut p = base_scoring();
    p.stream.addon_priority = Some(0);
    scoring_fixtures.push(scoring_fixture(
        "scoring/addon_priority:p0",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.stream.addon_priority = Some(2);
    scoring_fixtures.push(scoring_fixture(
        "scoring/addon_priority:p2",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let mut p = base_scoring();
    p.stream.addon_priority = Some(5);
    scoring_fixtures.push(scoring_fixture(
        "scoring/addon_priority:p5",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    let p = base_scoring();
    scoring_fixtures.push(scoring_fixture(
        "scoring/addon_priority:none",
        p,
        &empty_opts(),
        &empty_corpus(),
        None,
    ));

    // ======================================================================
    // CORPUS STATS — 3 scenarios (scoring.rs:1729-1776)
    // ======================================================================

    let mut a = base_scoring();
    a.source = Source::CAM;
    a.cached.insert("rd".to_string(), true);
    let mut b = base_scoring();
    b.source = Source::WebDl;
    b.seeders = Some(100);
    let mut c = base_scoring();
    c.source = Source::HDTV;
    c.seeders = Some(5);
    let mut d = base_scoring();
    d.source = Source::BluRay;
    d.stream.url = Some("https://example.com/x".to_string());
    corpus_fixtures.push(corpus_fixture(
        "corpus/corpus_stats_basic_fractions",
        &[a, b, c, d],
        &ScoreOptions {
            active_debrids: vec!["rd".to_string()],
            ..Default::default()
        },
    ));

    corpus_fixtures.push(corpus_fixture(
        "corpus/corpus_stats_empty_avoids_divide_by_zero",
        &[],
        &ScoreOptions::default(),
    ));

    let mut streams = Vec::new();
    for sz in [1u64, 5, 10, 50, 100] {
        let mut p = base_scoring();
        p.size = Some(sz);
        streams.push(p);
    }
    corpus_fixtures.push(corpus_fixture(
        "corpus/corpus_stats_size_percentiles",
        &streams,
        &ScoreOptions::default(),
    ));

    // ======================================================================
    // RANKING — 5 scenarios (scoring.rs:1603-1869); tier_assignment_edge_cases
    // was folded into the scoring tier fixtures above.
    // ======================================================================

    let scored = |p: ParsedStream, score: f64, tier: Tier| ScoredStream {
        parsed: p,
        score,
        reasons: vec![],
        tier,
    };

    // rank_and_pick_picks_cached_top_tier
    let mut p1 = base_scoring();
    p1.resolution = Resolution::P1080;
    let s1 = scored(p1, 30.0, Tier::P1080);
    let mut p2 = base_scoring();
    p2.resolution = Resolution::UHD;
    p2.cached.insert("rd".to_string(), true);
    let s2 = scored(p2, 90.0, Tier::Uhd);
    let mut p3 = base_scoring();
    p3.resolution = Resolution::P720;
    p3.cached.insert("rd".to_string(), true);
    let s3 = scored(p3, 50.0, Tier::P720);
    ranking_fixtures.push(ranking_fixture(
        "ranking/rank_and_pick_picks_cached_top_tier",
        vec![s1, s2, s3],
        &["rd".to_string()],
        false,
    ));

    // rank_and_pick_preserves_addon_order_when_no_cached
    let mut p1 = base_scoring();
    p1.resolution = Resolution::P1080;
    let s1 = scored(p1, 30.0, Tier::P1080);
    let mut p2 = base_scoring();
    p2.resolution = Resolution::UHD;
    let s2 = scored(p2, 40.0, Tier::Uhd);
    ranking_fixtures.push(ranking_fixture(
        "ranking/rank_and_pick_preserves_addon_order_when_no_cached",
        vec![s1, s2],
        &["rd".to_string()],
        false,
    ));

    // rank_and_pick_addon_order_preserves_return_index_over_score
    let mut p1 = base_scoring();
    p1.resolution = Resolution::P1080;
    p1.stream.addon_priority = Some(0);
    p1.stream.addon_return_idx = Some(0);
    p1.stream.url = Some("http://a/1080".to_string());
    let s1 = scored(p1, 30.0, Tier::P1080);
    let mut p2 = base_scoring();
    p2.resolution = Resolution::UHD;
    p2.stream.addon_priority = Some(0);
    p2.stream.addon_return_idx = Some(1);
    p2.stream.url = Some("http://a/4k".to_string());
    let s2 = scored(p2, 40.0, Tier::Uhd);
    ranking_fixtures.push(ranking_fixture(
        "ranking/rank_and_pick_addon_order_preserves_return_index_over_score",
        vec![s2, s1],
        &["rd".to_string()],
        true,
    ));

    // rank_and_pick_skips_theater_sources_for_primary
    let mut p1 = base_scoring();
    p1.source = Source::CAM;
    let s1 = scored(p1, 0.0, Tier::Rough);
    let mut p2 = base_scoring();
    p2.resolution = Resolution::P1080;
    let s2 = scored(p2, 0.0, Tier::P1080);
    ranking_fixtures.push(ranking_fixture(
        "ranking/rank_and_pick_skips_theater_sources_for_primary",
        vec![s1, s2],
        &[],
        false,
    ));

    // rank_and_pick_prefers_higher_scored_cached_regardless_of_input_order
    let mut backup = base_scoring();
    backup.cached.insert("rd".to_string(), true);
    backup.stream.addon_priority = Some(4);
    let s_backup = scored(backup, 80.0, Tier::P1080);
    let mut top = base_scoring();
    top.cached.insert("rd".to_string(), true);
    top.stream.addon_priority = Some(0);
    let s_top = scored(top, 92.0, Tier::P1080);
    ranking_fixtures.push(ranking_fixture(
        "ranking/rank_and_pick_prefers_higher_scored_cached_regardless_of_input_order",
        vec![s_backup, s_top],
        &["rd".to_string()],
        false,
    ));

    // ======================================================================
    // Assemble + write
    // ======================================================================

    let doc = json!({
        "generator": "harbor-core@0.1.0",
        "generatedAt": days_ago_iso(0.0),
        "note": "Golden vectors emitted by rust/vector-extractor replaying the harbor-core #[test] scenarios through the real core functions. Time-relative options carry 'releaseDateDaysAgo' so the Swift harness can re-derive the ISO date at replay time.",
        "skipped": [
            {
                "test": "tokenize_decomposes_precomposed_accents",
                "reason": "Exercises the private trust::tokenize() helper directly; not reachable through the public apply_trust() API."
            }
        ],
        "parser": &parser_fixtures,
        "trust": &trust_fixtures,
        "scoring": &scoring_fixtures,
        "corpus": &corpus_fixtures,
        "ranking": &ranking_fixtures,
    });

    let out_path = std::env::var("STREAM_VECTORS_OUT").unwrap_or_else(|_| OUT_PATH.to_string());
    let out_dir = std::path::Path::new(&out_path)
        .parent()
        .expect("output path has parent");
    std::fs::create_dir_all(out_dir).expect("create fixture dir");
    std::fs::write(&out_path, serde_json::to_string_pretty(&doc).expect("serialize doc"))
        .expect("write fixture file");

    println!(
        "wrote {} (parser={}, trust={}, scoring={}, corpus={}, ranking={}, skipped={})",
        out_path,
        parser_fixtures.len(),
        trust_fixtures.len(),
        scoring_fixtures.len(),
        corpus_fixtures.len(),
        ranking_fixtures.len(),
        1
    );
}
