import XCTest
@testable import HarborIOS

// MARK: - Phase 10/11 tests: playback policy, resume, skip segments.

final class ResumeStoreTests: XCTestCase {

    func testWatchedThresholdMarksWatched() async {
        let store = ResumeStore(cache: AppCache())
        let progress = PlaybackProgress(
            metaId: "tt1", streamKey: "k1", positionSeconds: 850, durationSeconds: 1000
        )
        await store.save(progress)
        let loaded = await store.progress(metaId: "tt1")
        XCTAssertEqual(loaded?.watched, true, "85% threshold must mark watched")
        XCTAssertNil(loaded?.resumePosition, "watched items must not resume")
    }

    func testStubNotSaved() async {
        let store = ResumeStore(cache: AppCache())
        let progress = PlaybackProgress(
            metaId: "tt2", streamKey: "k2", positionSeconds: 100, durationSeconds: 120
        )
        await store.save(progress)
        let loaded = await store.progress(metaId: "tt2")
        XCTAssertNil(loaded, "sub-150s stubs must never be saved")
    }

    func testBelowMinPositionNotSaved() async {
        let store = ResumeStore(cache: AppCache())
        let progress = PlaybackProgress(
            metaId: "tt3", streamKey: "k3", positionSeconds: 3, durationSeconds: 6000
        )
        await store.save(progress)
        let loaded = await store.progress(metaId: "tt3")
        XCTAssertNil(loaded, "positions below 5s must not be saved")
    }

    func testEndedCountsAsWatched() async {
        let store = ResumeStore(cache: AppCache())
        let progress = PlaybackProgress(
            metaId: "tt4", streamKey: "k4", positionSeconds: 5999, durationSeconds: 6000
        )
        await store.save(progress)
        let loaded = await store.progress(metaId: "tt4")
        XCTAssertEqual(loaded?.watched, true)
    }

    func testClearRemovesProgress() async {
        let store = ResumeStore(cache: AppCache())
        let progress = PlaybackProgress(
            metaId: "tt5", streamKey: "k5", positionSeconds: 500, durationSeconds: 6000
        )
        await store.save(progress)
        XCTAssertNotNil(await store.progress(metaId: "tt5"))
        await store.clear(metaId: "tt5")
        let loaded = await store.progress(metaId: "tt5")
        XCTAssertNil(loaded)
    }
}

final class SkipSegmentMergerTests: XCTestCase {

    func testMergePriorityFirstWins() {
        let duration = 1500.0
        // Overlapping aniSkip + introdb segments: aniSkip wins (higher priority).
        let aniSkip = [SkipSegment(startSeconds: 85, endSeconds: 175, kind: .intro, source: .aniskip)]
        let introDB = [SkipSegment(startSeconds: 80, endSeconds: 180, kind: .intro, source: .introdb)]
        let merged = SkipSegmentMerger.merge(aniSkip: aniSkip, introDB: introDB, chapters: [], durationSeconds: duration)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.source, .aniskip)
    }

    func testOutroBeforeHalfDropped() {
        let duration = 2000.0
        let early = SkipSegment(startSeconds: 100, endSeconds: 200, kind: .outro, source: .chapters)
        let late = SkipSegment(startSeconds: 1500, endSeconds: 1600, kind: .outro, source: .chapters)
        let merged = SkipSegmentMerger.merge(aniSkip: [], introDB: [], chapters: [early, late], durationSeconds: duration)
        XCTAssertEqual(merged.count, 1, "outro before 50% must be dropped")
        XCTAssertEqual(merged.first?.startSeconds, 1500)
    }

    func testLengthBounds() {
        let duration = 3000.0
        let tooShort = SkipSegment(startSeconds: 10, endSeconds: 11, kind: .intro, source: .chapters)
        let tooLong = SkipSegment(startSeconds: 100, endSeconds: 3000, kind: .intro, source: .chapters)
        let good = SkipSegment(startSeconds: 100, endSeconds: 200, kind: .intro, source: .chapters)
        let merged = SkipSegmentMerger.merge(aniSkip: [], introDB: [], chapters: [tooShort, tooLong, good], durationSeconds: duration)
        XCTAssertEqual(merged.map(\.id), [good.id], "only 2–360s segments survive")
    }

    func testActiveSegmentTailMargin() {
        let seg = SkipSegment(startSeconds: 100, endSeconds: 200, kind: .intro, source: .aniskip)
        let segments = [seg]
        XCTAssertNil(SkipSegmentMerger.activeSegment(at: 99, in: segments))
        XCTAssertEqual(SkipSegmentMerger.activeSegment(at: 100, in: segments), seg)
        XCTAssertEqual(SkipSegmentMerger.activeSegment(at: 199, in: segments), seg)
        XCTAssertNil(SkipSegmentMerger.activeSegment(at: 199.5, in: segments), "0.75s tail margin")
    }

    func testChapterClassification() {
        let chapters = [
            ChapterInfo(title: "Previously on...", startSeconds: 0, endSeconds: 30),
            ChapterInfo(title: "Opening", startSeconds: 30, endSeconds: 120),
            ChapterInfo(title: "Ending", startSeconds: 1200, endSeconds: 1300),
            ChapterInfo(title: "Main Story", startSeconds: 120, endSeconds: 1200),
        ]
        let segments = ChapterSkipClassifier.segments(from: chapters, durationSeconds: 1400)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].kind, .recap)
        XCTAssertEqual(segments[1].kind, .intro)
        XCTAssertEqual(segments[2].kind, .outro)
    }
}

final class PlaybackPolicyTests: XCTestCase {

    func testHarborConstants() {
        XCTAssertEqual(PlaybackPolicy.watchedRatio, 0.85)
        XCTAssertEqual(PlaybackPolicy.maxAutoretryAttempts, 5)
        XCTAssertEqual(PlaybackPolicy.stubMaxSeconds, 150)
        XCTAssertEqual(PlaybackPolicy.slowLoadSeconds, 50)
        XCTAssertEqual(PlaybackPolicy.frozenPositionStartedSeconds, 18)
        XCTAssertEqual(PlaybackPolicy.blackScreenGraceSeconds, 6)
        XCTAssertEqual(PlaybackPolicy.chromeHideWhenPlaying, 1.8)
        XCTAssertEqual(PlaybackPolicy.sleepTimerPresetsMinutes, [15, 30, 45, 60, 120, 180, 240, 360])
    }
}
