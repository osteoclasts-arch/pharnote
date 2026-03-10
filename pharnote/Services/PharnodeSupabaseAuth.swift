import Combine
import Foundation
import Security

struct PharnodeSupabaseSession: Codable, Hashable, Sendable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var expiresAt: Date
    var userID: String
    var userEmail: String?
}

struct PharnodeSupabaseConfiguration: Codable, Hashable, Sendable {
    var baseURLString: String

    static let `default` = PharnodeSupabaseConfiguration(
        baseURLString: "https://djxxqvglkqqpkmbudksr.supabase.co"
    )

    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRqeHhxdmdsa3FxcGttYnVka3NyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU1ODI1MTUsImV4cCI6MjA4MTE1ODUxNX0.2nm49QCawrtpyRsLhybCd3L0DwUs5XGSeBo9Fj9S51M"
}

private struct PharnodeSupabaseAuthResponse: Codable {
    struct User: Codable {
        var id: String
        var email: String?
    }

    var access_token: String
    var refresh_token: String
    var expires_in: Int?
    var expires_at: TimeInterval?
    var token_type: String?
    var user: User?
}

private struct PharnodeSupabaseLogoutRequest: Encodable {
    var scope: String = "global"
}

private final class PharnodeSupabaseSessionStore {
    private let service = "nodephar.pharnote.supabase.auth"
    private let account = "session"

    func load() -> PharnodeSupabaseSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PharnodeSupabaseSession.self, from: data)
    }

    func save(_ session: PharnodeSupabaseSession?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        guard let session else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }

        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
}

private struct PharnodeSupabaseAuthClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func signIn(email: String, password: String, configuration: PharnodeSupabaseConfiguration) async throws -> PharnodeSupabaseSession {
        try await requestSession(
            path: "/auth/v1/token?grant_type=password",
            configuration: configuration,
            authorizationToken: nil,
            body: [
                "email": email,
                "password": password
            ]
        )
    }

    func refresh(refreshToken: String, configuration: PharnodeSupabaseConfiguration) async throws -> PharnodeSupabaseSession {
        try await requestSession(
            path: "/auth/v1/token?grant_type=refresh_token",
            configuration: configuration,
            authorizationToken: nil,
            body: [
                "refresh_token": refreshToken
            ]
        )
    }

    func signOut(accessToken: String, configuration: PharnodeSupabaseConfiguration) async {
        guard let baseURL = URL(string: configuration.baseURLString) else { return }
        let endpoint = baseURL.appending(path: "/auth/v1/logout")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(PharnodeSupabaseConfiguration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        request.httpBody = try? encoder.encode(PharnodeSupabaseLogoutRequest())
        _ = try? await session.data(for: request)
    }

    private func requestSession(
        path: String,
        configuration: PharnodeSupabaseConfiguration,
        authorizationToken: String?,
        body: [String: String]
    ) async throws -> PharnodeSupabaseSession {
        guard let baseURL = URL(string: configuration.baseURLString) else {
            throw URLError(.badURL)
        }
        let endpoint = baseURL.appending(path: path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(PharnodeSupabaseConfiguration.anonKey, forHTTPHeaderField: "apikey")
        if let authorizationToken {
            request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw NSError(domain: "PharnodeSupabaseAuth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PharnodeSupabaseAuthResponse.self, from: data)

        let expiresAt: Date
        if let expiresAtValue = decoded.expires_at {
            expiresAt = Date(timeIntervalSince1970: expiresAtValue)
        } else {
            expiresAt = Date().addingTimeInterval(TimeInterval(decoded.expires_in ?? 3600))
        }

        return PharnodeSupabaseSession(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            tokenType: decoded.token_type ?? "bearer",
            expiresAt: expiresAt,
            userID: decoded.user?.id ?? "",
            userEmail: decoded.user?.email
        )
    }
}

@MainActor
final class PharnodeSupabaseAuthManager: ObservableObject {
    @Published private(set) var configuration: PharnodeSupabaseConfiguration
    @Published private(set) var session: PharnodeSupabaseSession?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let userDefaults: UserDefaults
    private let sessionStore: PharnodeSupabaseSessionStore
    private let client: PharnodeSupabaseAuthClient
    private let configurationKey = "pharnode_supabase_auth_configuration"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.sessionStore = PharnodeSupabaseSessionStore()
        self.client = PharnodeSupabaseAuthClient()
        self.configuration = Self.loadConfiguration(from: userDefaults, key: configurationKey)
        self.session = self.sessionStore.load()

        Task {
            _ = await refreshSessionIfNeeded()
        }
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var authenticatedEmail: String? {
        session?.userEmail
    }

    var userID: String? {
        session?.userID
    }

    func updateBaseURL(_ baseURLString: String) {
        configuration = PharnodeSupabaseConfiguration(
            baseURLString: normalizedURLString(baseURLString)
        )
        persistConfiguration()
    }

    func signIn(email: String, password: String, baseURLString: String) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !normalizedPassword.isEmpty else {
            errorMessage = "이메일과 비밀번호를 입력해야 합니다."
            return false
        }

        updateBaseURL(baseURLString)
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let signedInSession = try await client.signIn(
                email: normalizedEmail,
                password: normalizedPassword,
                configuration: configuration
            )
            session = signedInSession
            sessionStore.save(signedInSession)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "로그인 실패: \(error.localizedDescription)"
            return false
        }
    }

    func signOut() async {
        if let accessToken = session?.accessToken {
            await client.signOut(accessToken: accessToken, configuration: configuration)
        }
        session = nil
        sessionStore.save(nil)
        errorMessage = nil
    }

    func validAccessToken() async -> String? {
        let refreshed = await refreshSessionIfNeeded()
        guard refreshed else { return nil }
        return session?.accessToken
    }

    func handleAppDidBecomeActive() async {
        _ = await refreshSessionIfNeeded()
    }

    func refreshSessionIfNeeded(force: Bool = false) async -> Bool {
        guard let currentSession = session else { return false }

        if !force && currentSession.expiresAt > Date().addingTimeInterval(60 * 5) {
            return true
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let refreshedSession = try await client.refresh(
                refreshToken: currentSession.refreshToken,
                configuration: configuration
            )
            session = refreshedSession
            sessionStore.save(refreshedSession)
            errorMessage = nil
            return true
        } catch {
            session = nil
            sessionStore.save(nil)
            errorMessage = "세션 갱신 실패: \(error.localizedDescription)"
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func persistConfiguration() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(configuration) {
            userDefaults.set(data, forKey: configurationKey)
        }
    }

    private func normalizedURLString(_ candidate: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return PharnodeSupabaseConfiguration.default.baseURLString }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return normalized
        }
        return "https://\(normalized)"
    }

    private static func loadConfiguration(from userDefaults: UserDefaults, key: String) -> PharnodeSupabaseConfiguration {
        guard let data = userDefaults.data(forKey: key) else { return .default }
        let decoder = JSONDecoder()
        return (try? decoder.decode(PharnodeSupabaseConfiguration.self, from: data)) ?? .default
    }
}
