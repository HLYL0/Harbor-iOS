import Foundation

// MARK: - NetworkClient (Phase 3).
// URLSession wrapper: privacy blocklist enforcement, timeout, bounded retry with
// exponential backoff + jitter, cancellation propagation. Mirrors Harbor's safeFetch
// contract (TrackerBlockedError + blocked counter) and its retry norms (audit §1).

struct RetryPolicy: Sendable {
    var maxAttempts: Int          // total attempts including the first
    var baseDelay: TimeInterval   // seconds
    var maxDelay: TimeInterval
    var retryableStatusCodes: Set<Int>
    var retryOnNetworkError: Bool

    init(
        maxAttempts: Int = 2,
        baseDelay: TimeInterval = 0.5,
        maxDelay: TimeInterval = 5,
        retryableStatusCodes: Set<Int> = [408, 425, 429, 500, 502, 503, 504],
        retryOnNetworkError: Bool = true
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.retryableStatusCodes = retryableStatusCodes
        self.retryOnNetworkError = retryOnNetworkError
    }

    static let none = RetryPolicy(maxAttempts: 1, retryOnNetworkError: false)
    static let `default` = RetryPolicy()
}

enum NetworkClientError: Error, LocalizedError {
    case blocked(String)
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .blocked(let host): return "Blocked by privacy filter: \(host)"
        case .httpStatus(let code): return "Server returned HTTP \(code)"
        case .invalidResponse: return "Server returned an invalid response."
        }
    }
}

/// Transport abstraction so retry/backoff logic is unit-testable on CI.
protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkClientError.invalidResponse
        }
        return (data, http)
    }
}

actor NetworkClient {

    static let shared = NetworkClient()

    private let transport: any HTTPTransport
    private(set) var blockedRequestCount: Int = 0

    init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Full request: blocklist → transport → status/retry handling.
    func data(
        for request: URLRequest,
        policy: RetryPolicy = .default
    ) async throws -> (Data, HTTPURLResponse) {
        if let url = request.url, PrivacyBlocklist.isBlocked(url) {
            blockedRequestCount += 1
            throw NetworkClientError.blocked(url.host ?? url.absoluteString)
        }

        var attempt = 0
        var lastError: Error = NetworkClientError.invalidResponse
        while attempt < policy.maxAttempts {
            attempt += 1
            var outcome: (Data, HTTPURLResponse)?
            var failure: Error?
            do {
                outcome = try await transport.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failure = error
            }

            if let outcome {
                let status = outcome.1.statusCode
                if (200..<300).contains(status) {
                    return outcome
                }
                // Non-retryable status throws OUTSIDE the do-catch so it is never
                // swallowed by the retry handler (404 must not be retried).
                guard policy.retryableStatusCodes.contains(status) else {
                    throw NetworkClientError.httpStatus(status)
                }
                lastError = NetworkClientError.httpStatus(status)
            } else if let failure {
                lastError = failure
                guard policy.retryOnNetworkError else { throw failure }
            }

            if attempt >= policy.maxAttempts {
                throw lastError
            }
            try await Task.sleep(nanoseconds: UInt64(delaySeconds(attempt: attempt, policy: policy) * 1_000_000_000))
        }
        throw lastError
    }

    /// Convenience JSON getter with decoding + blocklist.
    func get<T: Decodable>(
        _ type: T.Type,
        url: URL,
        headers: [String: String] = [:],
        policy: RetryPolicy = .default
    ) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, _) = try await data(for: request, policy: policy)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Exponential backoff with full jitter, clamped to maxDelay.
    nonisolated func delaySeconds(attempt: Int, policy: RetryPolicy) -> Double {
        let exp = min(policy.maxDelay, policy.baseDelay * pow(2, Double(attempt - 1)))
        return Double.random(in: 0...exp)
    }
}
