import Foundation

public struct CursorAPIClient {
    public var apiKey: String
    public var baseURL: URL
    public var session: URLSession

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.cursor.com")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    public struct CreateAgentRequest: Encodable {
        public struct Prompt: Encodable {
            public var text: String
            public init(text: String) { self.text = text }
        }
        public struct Model: Encodable {
            public var id: String
            public init(id: String) { self.id = id }
        }
        public struct Repo: Encodable {
            public var url: String
            public var startingRef: String?
            public init(url: String, startingRef: String?) {
                self.url = url
                self.startingRef = startingRef
            }
        }

        public var prompt: Prompt
        public var model: Model?
        public var name: String?
        public var repos: [Repo]?
        public var autoCreatePR: Bool?

        public init(
            prompt: Prompt,
            model: Model? = nil,
            name: String? = nil,
            repos: [Repo]? = nil,
            autoCreatePR: Bool? = nil
        ) {
            self.prompt = prompt
            self.model = model
            self.name = name
            self.repos = repos
            self.autoCreatePR = autoCreatePR
        }
    }

    public struct CreateRunRequest: Encodable {
        public struct Prompt: Encodable {
            public var text: String
            public init(text: String) { self.text = text }
        }
        public var prompt: Prompt
        public init(prompt: Prompt) { self.prompt = prompt }
    }

    public struct AgentEnvelope: Decodable {
        public var agent: Agent
        public var run: Run?
    }

    public struct RunEnvelope: Decodable {
        public var run: Run
    }

    public struct Agent: Decodable, Equatable {
        public var id: String
        public var name: String?
        public var status: String?
        public var url: String?

        public init(id: String, name: String? = nil, status: String? = nil, url: String? = nil) {
            self.id = id
            self.name = name
            self.status = status
            self.url = url
        }
    }

    public struct Run: Decodable, Equatable {
        public var id: String
        public var agentId: String?
        public var status: String
        public var createdAt: String?
        public var updatedAt: String?
    }

    public enum APIError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case http(Int, String)
        case decoding(Error)
        case rateLimited(LimitSignal)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add your Cursor API key in Settings."
            case .invalidURL:
                return "Invalid API URL."
            case .http(let code, let body):
                return "Cursor API \(code): \(body.prefix(280))"
            case .decoding(let error):
                return "Could not decode Cursor response: \(error.localizedDescription)"
            case .rateLimited(let signal):
                return signal.reason
            case .transport(let error):
                return error.localizedDescription
            }
        }
    }

    public func createAgent(
        prompt: String,
        name: String?,
        repositoryURL: String?,
        startingRef: String?,
        modelId: String?,
        autoCreatePR: Bool
    ) async throws -> AgentEnvelope {
        var request = CreateAgentRequest(
            prompt: .init(text: prompt),
            model: nil,
            name: name,
            repos: nil,
            autoCreatePR: autoCreatePR
        )
        if let modelId, !modelId.isEmpty {
            request.model = .init(id: modelId)
        }
        if let repositoryURL, !repositoryURL.isEmpty {
            request.repos = [
                .init(url: repositoryURL, startingRef: startingRef?.nilIfEmpty)
            ]
        }
        return try await send(
            path: "/v1/agents",
            method: "POST",
            body: request,
            decode: AgentEnvelope.self
        )
    }

    public func createRun(agentId: String, prompt: String) async throws -> RunEnvelope {
        try await send(
            path: "/v1/agents/\(agentId)/runs",
            method: "POST",
            body: CreateRunRequest(prompt: .init(text: prompt)),
            decode: RunEnvelope.self
        )
    }

    public func getRun(agentId: String, runId: String) async throws -> RunEnvelope {
        try await send(
            path: "/v1/agents/\(agentId)/runs/\(runId)",
            method: "GET",
            body: Optional<String>.none,
            decode: RunEnvelope.self
        )
    }

    public func getAgent(agentId: String) async throws -> Agent {
        struct AgentOnly: Decodable { var id: String; var name: String?; var status: String?; var url: String? }
        let value: AgentOnly = try await send(
            path: "/v1/agents/\(agentId)",
            method: "GET",
            body: Optional<String>.none,
            decode: AgentOnly.self
        )
        return Agent(id: value.id, name: value.name, status: value.status, url: value.url)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
        decode: Response.Type
    ) async throws -> Response {
        guard !apiKey.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let token = Data("\(apiKey):".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = String(data: data, encoding: .utf8) ?? ""

            if let limit = LimitDetector.detect(statusCode: status, body: text) {
                throw APIError.rateLimited(limit)
            }

            guard (200..<300).contains(status) else {
                throw APIError.http(status, text)
            }

            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
