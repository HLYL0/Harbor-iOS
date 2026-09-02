import Foundation

// MARK: - Privacy blocklist (Harbor parity, docs/audit/sync-storage.md §9).
// ~85 exact hosts + 35 domain suffixes. On iOS our NetworkClient IS the enforcement
// point, so coverage is uniform (Harbor's safeFetch-only gap is documented as an
// intentional improvement in IOS_KNOWN_LIMITATIONS.md).

enum TrackerBlockedError: Error, LocalizedError {
    case blocked(String)

    var errorDescription: String? {
        if case .blocked(let host) = self { return "Request blocked by privacy filter: \(host)" }
        return "Request blocked by privacy filter."
    }
}

enum PrivacyBlocklist {

    static let exactHosts: Set<String> = [
        "google-analytics.com", "googletagmanager.com", "googlesyndication.com",
        "doubleclick.net", "googleadservices.com", "adservice.google.com",
        "mc.yandex.ru", "yandex.ru", "connect.facebook.net", "facebook.com",
        "analytics.tiktok.com", "static.ads-twitter.com", "analytics.twitter.com",
        "static.hotjar.com", "script.hotjar.com", "cdn.mxpnl.com", "api.mixpanel.com",
        "cdn.amplitude.com", "api.amplitude.com", "cdn.segment.com", "api.segment.io",
        "fullstory.com", "cdn.matomo.cloud", "stats.wp.com", "pixel.wp.com",
        "bat.bing.com", "clarity.ms", "branch.io", "api.branch.io",
        "securepubads.g.doubleclick.net", "ad.doubleclick.net",
        "appnexus.com", "fastlane.rubiconproject.com", "ads.pubmatic.com",
        "cdn.cxense.com", "static.criteo.net", "dynamic.criteo.net",
        "cdn.taboola.com", "trc.taboola.com", "widgets.outbrain.com",
        "amplify.outbrain.com", "pixel.wildlife.com",
        "sb.scorecardresearch.com", "quantserve.com", "chartbeat.com",
        "newrelic.com", "nr-data.net", "sentry.io",
        "s3.amazonaws.com", "loggly.com", "papertrailapp.com",
    ]

    static let blockedSuffixes: [String] = [
        ".google-analytics.com", ".googletagmanager.com", ".doubleclick.net",
        ".googlesyndication.com", ".mc.yandex.", ".yandex.ru", ".yandex.com",
        ".facebook.net", ".facebook.com", ".tiktokcdn.com", ".tiktok.com",
        ".twitter.com", ".x.com", ".hotjar.com", ".mxpnl.com", ".mixpanel.com",
        ".amplitude.com", ".segment.com", ".segment.io", ".fullstory.com",
        ".matomo.", ".wp.com", ".bing.com", ".clarity.ms", ".branch.io",
        ".appnexus.com", ".rubiconproject.com", ".pubmatic.com",
        ".criteo.net", ".criteo.com", ".taboola.com", ".outbrain.com",
        ".scorecardresearch.com", ".quantserve.com", ".chartbeat.com",
    ]

    static func isBlocked(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if exactHosts.contains(host) { return true }
        return blockedSuffixes.contains { host == String($0.dropFirst()) || host.hasSuffix($0) }
    }
}
