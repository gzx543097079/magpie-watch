import Foundation

enum MagpieAPIError: LocalizedError {
    case invalidResponse
    case server(Int)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Magpie 返回了无法识别的响应"
        case .server(let status):
            return "Magpie 接口返回 HTTP \(status)"
        case .decode(let message):
            return "Magpie 数据解析失败：\(message)"
        }
    }
}

struct MagpieAPI {
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:3425")!) {
        self.baseURL = baseURL
    }

    func service() async throws -> ServiceInfo {
        try await get(path: "/", as: ServiceInfo.self)
    }

    func usage(period: String = "today") async throws -> UsageResponse {
        try await get(
            path: "/v1/magpie/usage",
            query: [URLQueryItem(name: "period", value: period)],
            as: UsageResponse.self
        )
    }

    func quotas() async throws -> QuotasResponse {
        try await get(path: "/v1/magpie/quotas", as: QuotasResponse.self)
    }

    func trace() async throws -> TraceResponse {
        try await get(
            path: "/v1/magpie/trace",
            query: [URLQueryItem(name: "after", value: "0")],
            as: TraceResponse.self
        )
    }

    private func get<T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw MagpieAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MagpieAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MagpieAPIError.server(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MagpieAPIError.decode(error.localizedDescription)
        }
    }
}
