import Foundation
import os

/// Handles communication with the Claude API for trade analysis
actor ClaudeService {
    private static let logger = Logger(subsystem: "com.greenwick", category: "ClaudeService")

    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let session: URLSession

    /// Models used for different analysis types (billed to the user's own API key)
    enum Model: String, Sendable {
        case haiku = "claude-haiku-5-5"   // Daily summaries, quick insights
        case sonnet = "claude-sonnet-5-5" // Deep analysis, edge detection
    }

    init(apiKey: String) {
        self.apiKey = apiKey
        self.session = CertificatePinningDelegate.pinnedSession(timeout: 180)
    }

    // MARK: - API Communication

    struct Message: Codable, Sendable {
        let role: String
        let content: String
    }

    struct APIRequest: Codable, Sendable {
        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [Message]
        let output_config: OutputConfig?

        struct OutputConfig: Codable, Sendable {
            let effort: String
        }
    }

    struct APIResponse: Codable, Sendable {
        let content: [ContentBlock]
        let stop_reason: String?
        let usage: Usage?

        struct ContentBlock: Codable, Sendable {
            let type: String
            let text: String?
        }

        struct Usage: Codable, Sendable {
            let input_tokens: Int
            let output_tokens: Int
        }
    }

    /// Send a message to Claude and get a response
    func send(
        system: String? = nil,
        messages: [Message],
        model: Model = .sonnet,
        maxTokens: Int = 16000
    ) async throws -> String {
        let request = APIRequest(
            model: model.rawValue,
            max_tokens: maxTokens,
            system: system,
            messages: messages,
            output_config: .init(effort: "medium")
        )

        guard let apiURL = URL(string: baseURL) else {
            throw ClaudeError.invalidResponse
        }
        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            #if DEBUG
            let body = String(data: data.prefix(200), encoding: .utf8) ?? "Unknown"
            Self.logger.error("API error \(httpResponse.statusCode): \(body)")
            #else
            Self.logger.error("API error \(httpResponse.statusCode)")
            #endif
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode)
        }

        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("application/json") else {
            throw ClaudeError.invalidResponse
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

        if apiResponse.stop_reason == "refusal" {
            throw ClaudeError.refused
        }

        // The response can start with a (hidden) thinking block — join the text blocks only.
        let text = apiResponse.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
        guard !text.isEmpty else {
            throw ClaudeError.emptyResponse
        }

        if let usage = apiResponse.usage {
            Self.logger.info("Tokens: \(usage.input_tokens) in, \(usage.output_tokens) out")
        }

        return text
    }

    // MARK: - Errors

    enum ClaudeError: LocalizedError {
        case invalidResponse
        case apiError(statusCode: Int)
        case emptyResponse
        case refused
        case noAPIKey

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Invalid response from API"
            case .apiError(let code): "API error (\(code))"
            case .emptyResponse: "Empty response from API"
            case .refused: "The AI declined to answer this request. Try again later."
            case .noAPIKey: "No API key configured. Add your Anthropic API key in Settings."
            }
        }
    }
}
