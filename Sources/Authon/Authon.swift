// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Authon Swift SDK — Software Licensing & Authentication                    ║
// ║  Version: 1.0.0                                                            ║
// ║  Dependencies: Foundation (URLSession, no external packages)                ║
// ║                                                                            ║
// ║  Website: https://authon.pro                                               ║
// ║  Docs:    https://authon.pro/docs                                          ║
// ║  Discord: https://discord.gg/jMZCTKPsmE                                    ║
// ║  Status:  https://authon.pro/status                                        ║
// ║  Health:  https://api.authon.pro/health                                    ║
// ║  GitHub:  https://github.com/authonpro                                     ║
// ║                                                                            ║
// ║  Requirements: Swift 5.5+ (async/await), macOS 12+ / iOS 15+               ║
// ║                                                                            ║
// ║  Usage:                                                                    ║
// ║    let auth = Authon(appId: "app-id", apiKey: "api-key")                   ║
// ║    try await auth.initialize()                                              ║
// ║    let session = try await auth.login(username: "user", password: "pass")   ║
// ║    print("Welcome \(session.username)!")                                    ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

import Foundation
#if canImport(IOKit)
import IOKit
#endif

// MARK: - Error Types

/// Errors that can occur when using the Authon SDK.
public enum AuthonError: Error, LocalizedError {
    /// API returned an error message.
    case apiError(String)
    /// Network or connection error.
    case networkError(String)
    /// Failed to parse the API response.
    case parseError(String)
    /// Client is not in the expected state.
    case stateError(String)

    public var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "Authon API: \(msg)"
        case .networkError(let msg): return "Network: \(msg)"
        case .parseError(let msg): return "Parse: \(msg)"
        case .stateError(let msg): return "State: \(msg)"
        }
    }
}

// MARK: - Data Types

/// Session data returned after successful authentication.
public struct SessionData {
    /// Unique session token for API calls.
    public let sessionToken: String
    /// Authenticated username.
    public let username: String
    /// User's access level (0+).
    public let level: Int
    /// Subscription plan name.
    public let subscription: String
    /// Subscription expiration date (ISO 8601).
    public let expiresAt: String
}

/// Application info returned from init().
public struct AppInfo {
    /// Application name.
    public let name: String
    /// Application version.
    public let version: String
    /// Whether HWID locking is enabled.
    public let hwidLock: Bool
    /// Whether hash checking is enabled.
    public let hashCheck: Bool
}

/// File entry from listFiles.
public struct FileInfo {
    /// Unique file identifier.
    public let id: String
    /// File name.
    public let name: String
    /// File size in bytes.
    public let size: Int
    /// Minimum user level required.
    public let minLevel: Int
}

/// Online users data.
public struct OnlineData {
    /// Number of currently online users.
    public let count: Int
    /// List of online usernames.
    public let users: [String]
}

/// Application statistics.
public struct StatsData {
    public let totalUsers: Int
    public let onlineUsers: Int
    public let totalKeys: Int
    public let appVersion: String
}

/// Blacklist check result.
public struct BlacklistData {
    public let blacklisted: Bool
    public let reason: String?
}

/// Referral redemption result.
public struct ReferralData {
    public let expiresAt: String
    public let rewardDays: Int
    public let message: String
}

// MARK: - Client

/// Main Authon SDK client.
///
/// Provides full authentication, licensing, variable storage,
/// file downloads, and activity logging using async/await.
///
/// ```swift
/// let auth = Authon(appId: "your-app-id", apiKey: "your-api-key")
/// try await auth.initialize()
/// let session = try await auth.login(username: "user", password: "pass")
/// print("Level: \(session.level)")
/// ```
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public class Authon {

    // MARK: - Constants

    /// SDK version string.
    public static let version = "1.0.0"

    /// Default API endpoint URL.
    public static let defaultAPIURL = "https://api.authon.pro/v1"

    /// Default HTTP timeout.
    public static let defaultTimeout: TimeInterval = 15

    // MARK: - Properties

    private let appId: String
    private let apiKey: String
    private let apiURL: String
    private let session: URLSession

    /// Current session token. Nil if not authenticated.
    public private(set) var sessionToken: String?

    /// Authenticated username. Nil if not authenticated.
    public private(set) var username: String?

    /// User's access level (0+).
    public private(set) var level: Int = 0

    /// Subscription plan name.
    public private(set) var subscription: String?

    /// Subscription expiration date.
    public private(set) var expiresAt: String?

    /// Application name (set after init).
    public private(set) var appName: String?

    /// Application version (set after init).
    public private(set) var appVersion: String?

    /// Whether HWID lock is enabled.
    public private(set) var hwidLock: Bool = false

    /// Whether hash check is enabled.
    public private(set) var hashCheck: Bool = false

    /// Whether init() was called successfully.
    public private(set) var initialized: Bool = false

    /// Whether the client has an active session.
    public var isAuthenticated: Bool { sessionToken != nil }

    // MARK: - Initializer

    /// Creates a new Authon client.
    ///
    /// - Parameters:
    ///   - appId: Your Application ID from the Authon dashboard.
    ///   - apiKey: Your API Key from the Authon dashboard.
    ///   - apiURL: Custom API URL (default: https://api.authon.pro/v1).
    ///   - timeout: HTTP timeout interval (default: 15s).
    public init(appId: String, apiKey: String, apiURL: String = defaultAPIURL, timeout: TimeInterval = defaultTimeout) {
        precondition(!appId.isEmpty, "appId is required")
        precondition(!apiKey.isEmpty, "apiKey is required")

        self.appId = appId.trimmingCharacters(in: .whitespaces)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespaces)
        self.apiURL = apiURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "User-Agent": "Authon-Swift-SDK/\(Authon.version)"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - HWID Generation

    /// Generates a hardware ID unique to the current machine.
    ///
    /// macOS: Uses IOKit platform serial number.
    /// Other: Uses ProcessInfo hostname + architecture.
    ///
    /// - Returns: 32-character lowercase hex MD5 hash.
    public static func getHWID() -> String {
        var raw = ""

        #if os(macOS)
        // Use IOKit to get hardware UUID
        if let uuid = getIOPlatformUUID() {
            raw = uuid
        } else {
            raw = ProcessInfo.processInfo.hostName + ProcessInfo.processInfo.operatingSystemVersionString
        }
        #elseif os(iOS) || os(tvOS)
        // Use identifierForVendor on iOS
        if let id = UIDevice.current.identifierForVendor?.uuidString {
            raw = id
        } else {
            raw = ProcessInfo.processInfo.hostName
        }
        #else
        raw = ProcessInfo.processInfo.hostName + ProcessInfo.processInfo.operatingSystemVersionString
        #endif

        if raw.isEmpty {
            raw = "fallback-\(ProcessInfo.processInfo.hostName)"
        }

        return md5(raw)
    }

    #if os(macOS)
    private static func getIOPlatformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        if let uuid = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return uuid
        }
        return nil
    }
    #endif

    private static func md5(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: 16)

        _ = data.withUnsafeBytes { bytes in
            CC_MD5(bytes.baseAddress, CC_LONG(data.count), &digest)
        }

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Internal HTTP

    private func request(_ payload: [String: Any]) async throws -> [String: Any] {
        var body = payload
        body["appId"] = appId
        body["apiKey"] = apiKey

        guard let url = URL(string: apiURL) else {
            throw AuthonError.stateError("Invalid API URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: req)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthonError.parseError("Invalid response from server")
        }

        return json
    }

    private func checkSuccess(_ response: [String: Any]) throws {
        let success = response["success"] as? Bool ?? false
        if !success {
            let message = response["message"] as? String ?? "Unknown error"
            throw AuthonError.apiError(message)
        }
    }

    // MARK: - Initialization

    /// Initializes the connection to the Authon API.
    /// Must be called before any other API method.
    ///
    /// - Returns: AppInfo with application details.
    /// - Throws: AuthonError if initialization fails.
    @discardableResult
    public func initialize() async throws -> AppInfo {
        let response = try await request(["type": "init"])
        try checkSuccess(response)

        let data = response["data"] as? [String: Any] ?? [:]
        let info = AppInfo(
            name: data["name"] as? String ?? "",
            version: data["version"] as? String ?? "",
            hwidLock: data["hwidLock"] as? Bool ?? false,
            hashCheck: data["hashCheck"] as? Bool ?? false
        )

        appName = info.name
        appVersion = info.version
        hwidLock = info.hwidLock
        hashCheck = info.hashCheck
        initialized = true

        return info
    }

    // MARK: - Authentication

    /// Authenticates with username and password.
    ///
    /// - Parameters:
    ///   - username: User's username.
    ///   - password: User's password.
    ///   - hwid: Hardware ID (nil to auto-generate).
    /// - Returns: SessionData with user info.
    /// - Throws: AuthonError on failure (e.g., "Invalid credentials", "Account banned").
    public func login(username: String, password: String, hwid: String? = nil) async throws -> SessionData {
        guard !username.isEmpty, !password.isEmpty else {
            throw AuthonError.stateError("Username and password are required")
        }

        let response = try await request([
            "type": "login",
            "username": username,
            "password": password,
            "hwid": hwid ?? Authon.getHWID()
        ])
        try checkSuccess(response)

        let session = extractSession(response["data"] as? [String: Any] ?? [:])
        return session
    }

    /// Authenticates using a license key only.
    ///
    /// - Parameters:
    ///   - licenseKey: The license key.
    ///   - hwid: Hardware ID (nil to auto-generate).
    /// - Returns: SessionData.
    /// - Throws: AuthonError on failure.
    public func license(licenseKey: String, hwid: String? = nil) async throws -> SessionData {
        guard !licenseKey.isEmpty else {
            throw AuthonError.stateError("License key is required")
        }

        let response = try await request([
            "type": "license",
            "licenseKey": licenseKey,
            "hwid": hwid ?? Authon.getHWID()
        ])
        try checkSuccess(response)

        return extractSession(response["data"] as? [String: Any] ?? [:])
    }

    /// Registers a new user account with a license key.
    ///
    /// - Parameters:
    ///   - username: Desired username.
    ///   - password: Desired password.
    ///   - licenseKey: A valid, unused license key.
    ///   - hwid: Hardware ID (nil to auto-generate).
    /// - Throws: AuthonError on failure (e.g., "Username already exists").
    public func register(username: String, password: String, licenseKey: String, hwid: String? = nil) async throws {
        guard !username.isEmpty, !password.isEmpty, !licenseKey.isEmpty else {
            throw AuthonError.stateError("Username, password, and licenseKey are required")
        }

        let response = try await request([
            "type": "register",
            "username": username,
            "password": password,
            "licenseKey": licenseKey,
            "hwid": hwid ?? Authon.getHWID()
        ])
        try checkSuccess(response)
    }

    // MARK: - Session Management

    /// Validates the current session (heartbeat).
    ///
    /// - Returns: true if session is valid.
    public func check() async throws -> Bool {
        guard let token = sessionToken else { return false }

        let response = try await request([
            "type": "check",
            "sessionToken": token
        ])
        return response["success"] as? Bool ?? false
    }

    /// Ends the current session and clears local state.
    public func logout() async throws {
        guard let token = sessionToken else { return }

        let response = try await request([
            "type": "logout",
            "sessionToken": token
        ])

        if response["success"] as? Bool == true {
            sessionToken = nil
            username = nil
            level = 0
            subscription = nil
            expiresAt = nil
        }
    }

    // MARK: - Variables

    /// Gets an application-level variable.
    ///
    /// - Parameter key: Variable name.
    /// - Returns: Variable value or nil.
    public func getVar(key: String) async throws -> String? {
        let response = try await request([
            "type": "var",
            "key": key,
            "sessionToken": sessionToken ?? ""
        ])
        try checkSuccess(response)
        let data = response["data"] as? [String: Any] ?? [:]
        return data["value"] as? String
    }

    /// Sets a user-level variable.
    ///
    /// - Parameters:
    ///   - key: Variable name.
    ///   - value: Variable value.
    public func setVar(key: String, value: String) async throws {
        guard let token = sessionToken else {
            throw AuthonError.stateError("No active session")
        }

        let response = try await request([
            "type": "setvar",
            "key": key,
            "value": value,
            "sessionToken": token
        ])
        try checkSuccess(response)
    }

    /// Gets a user-level variable.
    ///
    /// - Parameter key: Variable name.
    /// - Returns: Variable value or nil.
    public func getUserVar(key: String) async throws -> String? {
        guard let token = sessionToken else {
            throw AuthonError.stateError("No active session")
        }

        let response = try await request([
            "type": "getvar",
            "key": key,
            "sessionToken": token
        ])
        try checkSuccess(response)
        let data = response["data"] as? [String: Any] ?? [:]
        return data["value"] as? String
    }

    // MARK: - Files

    /// Lists all files available to the authenticated user.
    ///
    /// - Returns: Array of FileInfo objects.
    public func listFiles() async throws -> [FileInfo] {
        guard let token = sessionToken else {
            throw AuthonError.stateError("No active session")
        }

        let response = try await request([
            "type": "list_files",
            "sessionToken": token
        ])
        try checkSuccess(response)

        guard let dataArray = response["data"] as? [[String: Any]] else {
            return []
        }

        return dataArray.map { item in
            FileInfo(
                id: item["id"] as? String ?? "",
                name: item["name"] as? String ?? "",
                size: item["size"] as? Int ?? 0,
                minLevel: item["minLevel"] as? Int ?? 0
            )
        }
    }

    /// Downloads a file by its ID.
    ///
    /// - Parameter fileId: File ID from listFiles().
    /// - Returns: Raw file data.
    public func downloadFile(fileId: String) async throws -> Data {
        guard let token = sessionToken, !fileId.isEmpty else {
            throw AuthonError.stateError("Session token and file ID are required")
        }

        var body: [String: Any] = [
            "type": "file",
            "appId": appId,
            "apiKey": apiKey,
            "fileId": fileId,
            "sessionToken": token
        ]

        guard let url = URL(string: apiURL) else {
            throw AuthonError.stateError("Invalid API URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: req)

        if let httpResponse = response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           contentType.contains("octet-stream") {
            return data
        }

        // Fallback: GET endpoint
        let getURLString = "\(apiURL)/files/download/\(fileId)?token=\(token)"
        guard let getURL = URL(string: getURLString) else {
            throw AuthonError.apiError("File download failed")
        }

        let (getData, getResponse) = try await session.data(from: getURL)
        if let httpResp = getResponse as? HTTPURLResponse,
           let ct = httpResp.value(forHTTPHeaderField: "Content-Type"),
           ct.contains("octet-stream") {
            return getData
        }

        throw AuthonError.apiError("File download failed")
    }

    // MARK: - Logging & Analytics

    /// Sends an activity log message to the dashboard.
    ///
    /// - Parameter message: Log message (max 500 chars).
    public func log(message: String) async throws {
        let msg = String(message.prefix(500))
        let response = try await request([
            "type": "log",
            "message": msg,
            "sessionToken": sessionToken ?? ""
        ])
        try checkSuccess(response)
    }

    /// Gets the list of currently online users.
    ///
    /// - Returns: OnlineData with count and users.
    public func fetchOnline() async throws -> OnlineData {
        guard let token = sessionToken else {
            throw AuthonError.stateError("No active session")
        }

        let response = try await request([
            "type": "fetch_online",
            "sessionToken": token
        ])
        try checkSuccess(response)

        let data = response["data"] as? [String: Any] ?? [:]
        return OnlineData(
            count: data["count"] as? Int ?? 0,
            users: data["users"] as? [String] ?? []
        )
    }

    /// Gets application statistics.
    ///
    /// - Returns: StatsData with totalUsers, onlineUsers, totalKeys, appVersion.
    public func fetchStats() async throws -> StatsData {
        guard let token = sessionToken else {
            throw AuthonError.stateError("No active session")
        }

        let response = try await request([
            "type": "fetch_stats",
            "sessionToken": token
        ])
        try checkSuccess(response)

        let data = response["data"] as? [String: Any] ?? [:]
        return StatsData(
            totalUsers: data["totalUsers"] as? Int ?? 0,
            onlineUsers: data["onlineUsers"] as? Int ?? 0,
            totalKeys: data["totalKeys"] as? Int ?? 0,
            appVersion: data["appVersion"] as? String ?? ""
        )
    }

    // MARK: - Security

    /// Checks if an IP or HWID is blacklisted.
    ///
    /// - Parameters:
    ///   - ip: IP address to check (nil to skip).
    ///   - hwid: Hardware ID to check (nil to skip).
    /// - Returns: BlacklistData.
    public func checkBlacklist(ip: String? = nil, hwid: String? = nil) async throws -> BlacklistData {
        var payload: [String: Any] = ["type": "check_blacklist"]
        if let ip = ip, !ip.isEmpty { payload["ip"] = ip }
        if let hwid = hwid, !hwid.isEmpty { payload["hwid"] = hwid }

        let response = try await request(payload)
        try checkSuccess(response)

        let data = response["data"] as? [String: Any] ?? [:]
        return BlacklistData(
            blacklisted: data["blacklisted"] as? Bool ?? false,
            reason: data["reason"] as? String
        )
    }

    /// Redeems a referral code for bonus subscription days.
    ///
    /// - Parameter code: Referral code.
    /// - Returns: ReferralData with expiresAt and rewardDays.
    public func redeemReferral(code: String) async throws -> ReferralData {
        guard let token = sessionToken, !code.isEmpty else {
            throw AuthonError.stateError("Session and referral code are required")
        }

        let response = try await request([
            "type": "redeem_referral",
            "code": code,
            "sessionToken": token
        ])
        try checkSuccess(response)

        let data = response["data"] as? [String: Any] ?? [:]
        return ReferralData(
            expiresAt: data["expiresAt"] as? String ?? "",
            rewardDays: data["rewardDays"] as? Int ?? 0,
            message: response["message"] as? String ?? ""
        )
    }

    // MARK: - Private Helpers

    private func extractSession(_ data: [String: Any]) -> SessionData {
        let session = SessionData(
            sessionToken: data["sessionToken"] as? String ?? "",
            username: data["username"] as? String ?? "",
            level: data["level"] as? Int ?? 0,
            subscription: data["subscription"] as? String ?? "",
            expiresAt: data["expiresAt"] as? String ?? ""
        )

        self.sessionToken = session.sessionToken
        self.username = session.username
        self.level = session.level
        self.subscription = session.subscription
        self.expiresAt = session.expiresAt

        return session
    }
}
