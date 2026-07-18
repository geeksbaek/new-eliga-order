import Foundation

@MainActor
final class APIClient {
    static let brandCode = "kakao"

    private let baseHost = "https://base.eligaorder.com"
    private let serviceHost = "https://svc.eligaorder.com"
    private let keychain: KeychainStore
    private let session: URLSession
    private var tokens: AuthTokens?
    private var cachedSpace: String?
    private var cookieSession = false

    init(keychain: KeychainStore = KeychainStore(), session: URLSession? = nil) {
        let resolvedSession = session ?? Self.makeSession()
        self.keychain = keychain
        self.session = resolvedSession

        let storedTokens = keychain.loadTokens()
        let cookieTokens = Self.extractTokens(
            from: .null,
            cookies: Self.authenticationCookies(in: resolvedSession)
        )
        self.tokens = storedTokens ?? cookieTokens
        self.cookieSession = self.tokens == nil && Self.hasAuthenticationCookie(in: resolvedSession)

        if storedTokens == nil, let cookieTokens {
            try? keychain.save(tokens: cookieTokens)
        }
    }

    var isAuthenticated: Bool {
        tokens?.accessToken.isEmpty == false
            || cookieSession
            || Self.hasAuthenticationCookie(in: session)
    }

    func signIn(userID: String, password: String) async throws {
        let space = try await resolveSpace()
        let body: JSONValue = .object([
            "userId": .string(userID),
            "password": .string(password),
            "brandCode": .string(Self.brandCode),
            "fcmToken": .string(PushTokenStore.deviceToken ?? "ios-native-new-eliga-order"),
        ])
        let json = try await request(
            path: "customer/sign-in",
            method: "POST",
            body: body,
            requiresAuthentication: false,
            allowsRefresh: false,
            knownSpace: space
        )

        if let extracted = Self.extractTokens(from: json, cookies: authenticationCookies()) {
            tokens = extracted
            try keychain.save(tokens: extracted)
        } else {
            cookieSession = true
        }
        _ = try await request(path: "customer/me", allowsRefresh: false)
    }

    func signOut() {
        tokens = nil
        cookieSession = false
        keychain.clear()
        session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    func request(
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: JSONValue? = nil,
        requiresAuthentication: Bool = true,
        allowsRefresh: Bool = true,
        knownSpace: String? = nil
    ) async throws -> JSONValue {
        let space: String
        if let knownSpace {
            space = knownSpace
        } else {
            space = try await resolveSpace()
        }
        let url = try makeServiceURL(space: space, path: path, query: query)
        let (data, response) = try await perform(
            url: url,
            method: method,
            body: body,
            requiresAuthentication: requiresAuthentication
        )

        if response.statusCode == 401, requiresAuthentication, allowsRefresh,
           try await refreshAccessToken() {
            return try await request(
                path: path,
                query: query,
                method: method,
                body: body,
                requiresAuthentication: true,
                allowsRefresh: false,
                knownSpace: space
            )
        }

        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401, requiresAuthentication { invalidateAuthentication() }
            throw APIError.http(
                status: response.statusCode,
                message: Self.errorMessage(from: data, status: response.statusCode)
            )
        }
        guard !data.isEmpty else { return .null }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    private func resolveSpace() async throws -> String {
        if let cachedSpace { return cachedSpace }
        var components = URLComponents(string: "\(baseHost)/space")
        components?.queryItems = [URLQueryItem(name: "brandCode", value: Self.brandCode)]
        guard let url = components?.url else { throw APIError.invalidURL }
        let (data, response) = try await perform(url: url, method: "GET", body: nil, requiresAuthentication: false)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(status: response.statusCode, message: Self.errorMessage(from: data, status: response.statusCode))
        }
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let space = json["content"].stringValue
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !space.isEmpty, space.unicodeScalars.allSatisfy(allowed.contains) else { throw APIError.invalidResponse }
        cachedSpace = space
        return space
    }

    private func refreshAccessToken() async throws -> Bool {
        guard let current = tokens, !current.refreshToken.isEmpty else { return false }
        do {
            let json = try await request(
                path: "customer/refresh-token",
                method: "POST",
                body: .object(["refreshToken": .string(current.refreshToken)]),
                requiresAuthentication: false,
                allowsRefresh: false
            )
            guard var refreshed = Self.extractTokens(from: json, cookies: authenticationCookies()) else {
                return false
            }
            if refreshed.refreshToken.isEmpty {
                refreshed = AuthTokens(
                    accessToken: refreshed.accessToken,
                    refreshToken: current.refreshToken,
                    tokenType: refreshed.tokenType
                )
            }
            tokens = refreshed
            try keychain.save(tokens: refreshed)
            return true
        } catch {
            return false
        }
    }

    private func perform(
        url: URL,
        method: String,
        body: JSONValue?,
        requiresAuthentication: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if requiresAuthentication, let accessToken = tokens?.accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return (data, httpResponse)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 128 * 1_024 * 1_024,
            diskPath: "com.leeari95.NewEligaOrder.api"
        )
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }

    private func makeServiceURL(space: String, path: String, query: [URLQueryItem]) throws -> URL {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: serviceHost)
        components?.path = "/\(space)/\(cleanPath)"
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw APIError.invalidURL }
        return url
    }

    static func extractTokens(from json: JSONValue, cookies: [HTTPCookie] = []) -> AuthTokens? {
        func search(_ value: JSONValue) -> AuthTokens? {
            let object = value.objectValue
            let access = ["accessToken", "access_token", "token"]
                .map { object[$0]?.stringValue ?? "" }
                .first { !$0.isEmpty }
            if let access {
                let refresh = object["refreshToken"]?.stringValue
                    ?? object["refresh_token"]?.stringValue
                    ?? ""
                let tokenType = object["tokenType"]?.stringValue ?? ""
                return AuthTokens(
                    accessToken: access,
                    refreshToken: refresh,
                    tokenType: tokenType.isEmpty ? "Bearer" : tokenType
                )
            }
            for key in ["content", "data", "result", "token"] {
                if let candidate = object[key], let found = search(candidate) { return found }
            }
            return nil
        }

        let bodyTokens = search(json)
        let cookieAccessToken = cookieValue(named: "AccessToken", in: cookies)
        let cookieRefreshToken = cookieValue(named: "RefreshToken", in: cookies)
        guard let accessToken = [bodyTokens?.accessToken, cookieAccessToken]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty })
        else { return nil }

        let responseRefreshToken = firstString(
            in: json,
            keys: ["refreshToken", "refresh_token"]
        )
        let refreshToken = [bodyTokens?.refreshToken, responseRefreshToken, cookieRefreshToken]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty })
            ?? ""
        let tokenType = bodyTokens?.tokenType.isEmpty == false ? bodyTokens?.tokenType : "Bearer"
        return AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType ?? "Bearer"
        )
    }

    private func authenticationCookies() -> [HTTPCookie] {
        Self.authenticationCookies(in: session)
    }

    private static func authenticationCookies(in session: URLSession) -> [HTTPCookie] {
        session.configuration.httpCookieStorage?.cookies?.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain == "eligaorder.com" || domain.hasSuffix(".eligaorder.com")
        } ?? []
    }

    private static func hasAuthenticationCookie(in session: URLSession) -> Bool {
        authenticationCookies(in: session).contains { cookie in
            ["accesstoken", "refreshtoken"].contains(cookie.name.lowercased())
                && !cookie.value.isEmpty
        }
    }

    private static func cookieValue(named name: String, in cookies: [HTTPCookie]) -> String? {
        cookies.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func firstString(in value: JSONValue, keys: Set<String>) -> String? {
        switch value {
        case .object(let object):
            for key in keys {
                let candidate = object[key]?.stringValue ?? ""
                if !candidate.isEmpty { return candidate }
            }
            for child in object.values {
                if let candidate = firstString(in: child, keys: keys) { return candidate }
            }
        case .array(let array):
            for child in array {
                if let candidate = firstString(in: child, keys: keys) { return candidate }
            }
        default:
            break
        }
        return nil
    }

    private func invalidateAuthentication() {
        signOut()
        onAuthenticationExpired?()
    }

    var onAuthenticationExpired: (() -> Void)?

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            let object = json.objectValue
            let detail = ["content", "message", "code", "error"]
                .map { object[$0]?.stringValue ?? "" }
                .first { !$0.isEmpty }
            if let detail {
                switch detail {
                case "LOGIN_USER_NOT_FOUND": return "등록되지 않은 계정이거나 이메일 형식이 올바르지 않습니다."
                case "LOGIN_PASSWORD_NOT_MATCHED", "LOGIN_PASSWORD_MISMATCH": return "비밀번호가 일치하지 않습니다."
                case "LOGIN_USER_LOCKED": return "잠긴 계정입니다. 엘리가 앱에서 확인해 주세요."
                default: return detail
                }
            }
        }
        if status == 401 { return "로그인이 필요합니다." }
        if status == 502 { return "엘리가 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요." }
        return "요청에 실패했습니다. (\(status))"
    }
}

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case network
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "잘못된 서버 주소입니다."
        case .invalidResponse: return "서버 응답을 읽지 못했습니다."
        case .network: return "네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .http(_, let message): return message
        }
    }
}
