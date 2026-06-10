import Foundation

// MARK: - Errors

enum ClaudeError: Error, LocalizedError {
    case noAPIKey
    case apiError(Int, String?)
    case parseError
    case timedOut
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key configured. Add it in Settings."
        case .apiError(let code, let details):
            if let details, !details.isEmpty {
                return "Claude API error (HTTP \(code)): \(details)"
            }
            return "Claude API error (HTTP \(code))"
        case .parseError:
            return "Could not parse Claude's response"
        case .timedOut:
            return "The request took too long and timed out. Please try again in a moment."
        case .network(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Service

enum ClaudeService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-sonnet-4-6"
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    // MARK: - Public API

    static func sendWithSystem(_ system: String, user: String, maxTokens: Int = 4096) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        return try await send(body: body)
    }

    static func send(messages: [[String: Any]], system: String? = nil, maxTokens: Int = 4096) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages
        ]
        if let system { body["system"] = system }
        return try await send(body: body)
    }

    // MARK: - Helpers

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let candidates = jsonCandidates(from: text)

        for candidate in candidates {
            guard let jsonData = candidate.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(type, from: jsonData) {
                return decoded
            }
        }

        throw ClaudeError.parseError
    }

    static func extractJSONPayload(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let fencePatterns = ["```json", "```JSON", "```"]
        for marker in fencePatterns {
            if let start = trimmed.range(of: marker),
               let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
                let payload = trimmed[start.upperBound..<end.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !payload.isEmpty { return payload }
            }
        }

        if let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }),
           let end = trimmed.lastIndex(where: { $0 == "}" || $0 == "]" }),
           start <= end {
            return String(trimmed[start...end])
        }

        return nil
    }

    private static func jsonCandidates(from text: String) -> [String] {
        guard let payload = extractJSONPayload(from: text) else { return [] }

        var candidates: [String] = [payload]
        let normalized = payload
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")

        if normalized != payload {
            candidates.append(normalized)
        }

        if let repaired = balancedJSONPrefix(from: normalized), repaired != normalized {
            candidates.append(repaired)
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    private static func balancedJSONPrefix(from text: String) -> String? {
        var stack: [Character] = []
        var inString = false
        var isEscaped = false
        var lastBalancedIndex: String.Index?

        for index in text.indices {
            let character = text[index]

            if inString {
                if isEscaped {
                    isEscaped = false
                    continue
                }
                if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                continue
            }

            if character == "{" || character == "[" {
                stack.append(character)
            } else if character == "}" {
                guard stack.last == "{" else { break }
                stack.removeLast()
            } else if character == "]" {
                guard stack.last == "[" else { break }
                stack.removeLast()
            }

            if stack.isEmpty {
                lastBalancedIndex = index
            }
        }

        guard let lastBalancedIndex else { return nil }
        return String(text[...lastBalancedIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internal

    private static func send(body: [String: Any]) async throws -> String {
        guard let apiKey = KeychainService.loadAnthropic() else { throw ClaudeError.noAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw ClaudeError.timedOut
            case .notConnectedToInternet:
                throw ClaudeError.network("You appear to be offline.")
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
                throw ClaudeError.network("Konomi couldn’t reach Anthropic. Check your connection and try again.")
            default:
                throw ClaudeError.network(error.localizedDescription)
            }
        } catch {
            throw ClaudeError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.parseError }
        guard http.statusCode == 200 else {
            throw ClaudeError.apiError(http.statusCode, extractAPIErrorMessage(from: data))
        }

        struct ClaudeResponse: Decodable {
            struct ContentBlock: Decodable { let type: String; let text: String? }
            let content: [ContentBlock]
        }
        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClaudeError.parseError }
        return text
    }

    private static func extractAPIErrorMessage(from data: Data) -> String? {
        struct APIErrorEnvelope: Decodable {
            struct APIError: Decodable { let message: String? }
            let error: APIError?
        }
        if let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           let message = decoded.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return String(text.prefix(200))
        }
        return nil
    }
}
