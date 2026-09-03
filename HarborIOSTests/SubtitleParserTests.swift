import XCTest
@testable import HarborIOS

// MARK: - Phase 11 subtitle tests: SRT/VTT/ASS parsing, encoding, time shift, Arabic.

final class SubtitleParserTests: XCTestCase {

    func testSRTBasic() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Hello world

        2
        00:00:05,500 --> 00:00:08,000
        Second line
        """
        let cues = SubtitleParser.parseSRT(srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].startSeconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].endSeconds, 4.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "Hello world")
        XCTAssertEqual(cues[1].startSeconds, 5.5, accuracy: 0.001)
    }

    func testSRTDotSeparatorAndHours() {
        let srt = "1\n01:02:03.456 --> 01:02:10.000\nA\n"
        let cues = SubtitleParser.parseSRT(srt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].startSeconds, 3723.456, accuracy: 0.001)
    }

    func testSRTMultilineText() {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nLine one\nLine two\n"
        let cues = SubtitleParser.parseSRT(srt)
        XCTAssertEqual(cues[0].text, "Line one Line two")
    }

    func testVTTWithTagsAndSettings() {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000 line:0 position:20%
        <v Roger>Hello</v>

        00:00:05.000 --> 00:00:08.000
        <i>Italic</i> text
        """
        let cues = SubtitleParser.parseVTT(vtt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Hello")
        XCTAssertEqual(cues[1].text, "Italic text")
    }

    func testASSParsing() {
        let ass = """
        [Script Info]
        Title: Test

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,{\\an8}Top text
        Dialogue: 0,0:00:05.00,0:00:09.00,Default,,0,0,0,,Line one\\NLine two
        """
        let cues = SubtitleParser.parseASS(ass)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].startSeconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "Top text")
        XCTAssertEqual(cues[1].text, "Line one\nLine two")
    }

    func testFormatDetection() {
        XCTAssertEqual(SubtitleParser.detectFormat("[Script Info]\nTitle: x\n[Events]"), .ass)
        XCTAssertEqual(SubtitleParser.detectFormat("WEBVTT\n\n00:00:01.000 --> 00:00:02.000"), .vtt)
        XCTAssertEqual(SubtitleParser.detectFormat("1\n00:00:01,000 --> 00:00:02,000\nX"), .srt)
    }

    func testEncodingUTF16ToUTF8() {
        let text = "مرحبا بالعالم"
        let data = Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!
        XCTAssertEqual(SubtitleParser.decodeNormalized(data), text)
    }

    func testEncodingUTF8BOMStripped() {
        let text = "Hello"
        let data = Data([0xEF, 0xBB, 0xBF]) + text.data(using: .utf8)!
        XCTAssertEqual(SubtitleParser.decodeNormalized(data), text)
    }

    func testWindows1256ArabicFallback() {
        // "مرحبا" in windows-1256: E3 D1 CD C7
        let data = Data([0xE3, 0xD1, 0xCD, 0xC8, 0xC7])   // م ر ح ب ا (5 bytes)
        let decoded = SubtitleParser.decodeNormalized(data)
        XCTAssertEqual(decoded, "مرحبا")
    }

    func testTimeShift() {
        let cues = [
            SubtitleCue(startSeconds: 1, endSeconds: 3, text: "A"),
            SubtitleCue(startSeconds: 5, endSeconds: 8, text: "B"),
        ]
        let shifted = SubtitleParser.applyTimeShift(cues, offsetMs: 2000)
        XCTAssertEqual(shifted[0].startSeconds, 3.0, accuracy: 0.001)
        XCTAssertEqual(shifted[1].startSeconds, 7.0, accuracy: 0.001)
    }

    func testSRTSerializationRoundTrip() {
        let cues = [
            SubtitleCue(startSeconds: 61.5, endSeconds: 65.25, text: "One"),
        ]
        let serialized = SubtitleParser.serializeSRT(cues)
        XCTAssertTrue(serialized.contains("00:01:01,500 --> 00:01:05,250"))
        let reparsed = SubtitleParser.parseSRT(serialized)
        XCTAssertEqual(reparsed.count, 1)
        XCTAssertEqual(reparsed[0].startSeconds, 61.5, accuracy: 0.001)
    }

    func testMalformedInputsDoNotCrash() {
        XCTAssertEqual(SubtitleParser.parseSRT("garbage\n\n\n"), [])
        XCTAssertEqual(SubtitleParser.parseSRT("1\nnot a time --> also not\nx"), [])
        XCTAssertEqual(SubtitleParser.parseVTT(""), [])
        XCTAssertEqual(SubtitleParser.parseASS("no dialogue here"), [])
        XCTAssertEqual(SubtitleParser.parse(""), [])
    }
}
