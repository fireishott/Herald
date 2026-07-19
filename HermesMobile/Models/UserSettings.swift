import Foundation

struct AppBuildConfiguration: Equatable, Sendable {
    let hostedRelayBaseURL: String?
    let hostedRelayEnabled: Bool
    let supportURL: URL?
    let termsOfServiceURL: URL?
    let privacyPolicyURL: URL?

    static func current(bundle: Bundle = .main) -> AppBuildConfiguration {
        let info = bundle.infoDictionary ?? [:]
        let hostedRelayBaseURL = RelayConfiguration.normalizeBaseURL(
            info["APP_HOSTED_RELAY_URL"] as? String
        )
        let hostedRelayEnabled = (info["APP_HOSTED_RELAY_ENABLED"] as? Bool) ?? false

        func urlValue(_ key: String) -> URL? {
            guard let raw = info[key] as? String, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return URL(string: raw)
        }

        return AppBuildConfiguration(
            hostedRelayBaseURL: hostedRelayBaseURL,
            hostedRelayEnabled: hostedRelayEnabled && hostedRelayBaseURL != nil,
            supportURL: urlValue("APP_SUPPORT_URL"),
            termsOfServiceURL: urlValue("APP_TERMS_URL"),
            privacyPolicyURL: urlValue("APP_PRIVACY_URL")
        )
    }
}

enum RelayMode: String, Codable, CaseIterable, Hashable, Sendable {
    case custom
    case hosted

    var displayLabel: String {
        switch self {
        case .custom: "Use My Relay"
        case .hosted: "Use Hosted Relay"
        }
    }
}

struct RelayConfiguration: Codable, Hashable, Sendable {
    var relayMode: RelayMode
    var customRelayBaseURL: String
    var hostedRelayBaseURL: String?
    var hostedRelayEnabled: Bool

    init(
        relayMode: RelayMode = .custom,
        customRelayBaseURL: String = "",
        hostedRelayBaseURL: String? = nil,
        hostedRelayEnabled: Bool = false
    ) {
        self.relayMode = relayMode
        self.customRelayBaseURL = RelayConfiguration.normalizeBaseURL(customRelayBaseURL) ?? customRelayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hostedRelayBaseURL = RelayConfiguration.normalizeBaseURL(hostedRelayBaseURL)
        self.hostedRelayEnabled = hostedRelayEnabled && self.hostedRelayBaseURL != nil
        if relayMode == .hosted && !self.canUseHosted {
            self.relayMode = .custom
        }
    }

    static func defaultValue(
        buildConfiguration: AppBuildConfiguration = .current(),
        environmentPolicy: AppEnvironmentPolicy = .currentBuild
    ) -> RelayConfiguration {
        RelayConfiguration(
            relayMode: .custom,
            customRelayBaseURL: environmentPolicy.allowsEnvironmentOverrides ? AppEnvironment.development.baseURLString : "",
            hostedRelayBaseURL: buildConfiguration.hostedRelayBaseURL,
            hostedRelayEnabled: buildConfiguration.hostedRelayEnabled
        )
    }

    static func migratedLegacyValue(
        environment: AppEnvironment,
        buildConfiguration: AppBuildConfiguration = .current(),
        environmentPolicy: AppEnvironmentPolicy = .currentBuild
    ) -> RelayConfiguration {
        if environmentPolicy.allowsEnvironmentOverrides, environment != .production {
            return RelayConfiguration(
                relayMode: .custom,
                customRelayBaseURL: environment.baseURLString,
                hostedRelayBaseURL: buildConfiguration.hostedRelayBaseURL,
                hostedRelayEnabled: buildConfiguration.hostedRelayEnabled
            )
        }

        if buildConfiguration.hostedRelayEnabled, buildConfiguration.hostedRelayBaseURL != nil {
            return RelayConfiguration(
                relayMode: .hosted,
                customRelayBaseURL: "",
                hostedRelayBaseURL: buildConfiguration.hostedRelayBaseURL,
                hostedRelayEnabled: true
            )
        }

        return RelayConfiguration.defaultValue(
            buildConfiguration: buildConfiguration,
            environmentPolicy: environmentPolicy
        )
    }

    mutating func applyBuildConfiguration(_ buildConfiguration: AppBuildConfiguration) {
        hostedRelayBaseURL = buildConfiguration.hostedRelayBaseURL
        hostedRelayEnabled = buildConfiguration.hostedRelayEnabled && hostedRelayBaseURL != nil
        customRelayBaseURL = RelayConfiguration.normalizeBaseURL(customRelayBaseURL) ?? customRelayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if relayMode == .hosted && !canUseHosted {
            relayMode = .custom
        }
    }

    var canUseHosted: Bool {
        hostedRelayEnabled && hostedRelayBaseURL != nil
    }

    var activeBaseURLString: String? {
        switch relayMode {
        case .custom:
            return RelayConfiguration.normalizeBaseURL(customRelayBaseURL)
        case .hosted:
            guard canUseHosted else { return RelayConfiguration.normalizeBaseURL(customRelayBaseURL) }
            return hostedRelayBaseURL
        }
    }

    var relayOriginLabel: String {
        guard let baseURLString = activeBaseURLString, let url = URL(string: baseURLString) else {
            return "Not Configured"
        }
        return url.host ?? baseURLString
    }

    var validationMessage: String? {
        switch relayMode {
        case .custom:
            let trimmed = customRelayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "Enter your relay URL." }
            guard RelayConfiguration.normalizeBaseURL(trimmed) != nil else {
                return "Relay URL must be an absolute http(s) URL ending with /v1."
            }
            return nil
        case .hosted:
            return canUseHosted ? nil : "Hosted relay is not configured in this app build."
        }
    }

    static func normalizeBaseURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.hasPrefix("http://"), !trimmed.hasPrefix("https://") {
            return nil
        }

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            return nil
        }

        let normalizedPath: String
        switch components.path {
        case "", "/":
            normalizedPath = "/v1"
        default:
            normalizedPath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        }
        guard normalizedPath.hasSuffix("/v1") else {
            return nil
        }
        components.path = normalizedPath
        return components.string
    }
}

struct AppEnvironmentPolicy: Equatable, Sendable {
    let allowsEnvironmentOverrides: Bool

    var availableEnvironments: [AppEnvironment] {
        allowsEnvironmentOverrides ? AppEnvironment.allCases : [.production]
    }

    var defaultEnvironment: AppEnvironment {
        .production
    }

    func sanitize(_ settings: UserSettings) -> UserSettings {
        var sanitized = settings
        if !availableEnvironments.contains(sanitized.environment) {
            sanitized.environment = defaultEnvironment
        }
        return sanitized
    }

    static let currentBuild: AppEnvironmentPolicy = {
        #if DEBUG
        AppEnvironmentPolicy(allowsEnvironmentOverrides: true)
        #else
        AppEnvironmentPolicy(allowsEnvironmentOverrides: false)
        #endif
    }()
}

enum LocationSyncPreference: String, Codable, Hashable, Sendable {
    case foregroundOnly
    case backgroundAllowed

    var displayLabel: String {
        switch self {
        case .foregroundOnly: "Foreground Only"
        case .backgroundAllowed: "Background Allowed"
        }
    }
}

/// The chat background a user has selected.
///
/// Every case is rendered procedurally in SwiftUI rather than shipped as a baked
/// image asset — gradients/textures are `LinearGradient`/`RadialGradient`/`Canvas`
/// drawing, keyed off this enum. See `ChatWallpaperBackground` in
/// `Core/Theme.swift`, which is the single rendering primitive later tasks
/// (chat wallpaper rendering, wallpaper picker) should consume for every case,
/// at any frame size (full-screen background or a small picker thumbnail).
///
/// There is intentionally no `thumbnailName`/asset-name property: nothing here
/// is backed by a named image in the asset catalog. `.custom` carries the raw
/// image bytes the user picked from their photo library.
enum ChatWallpaper: Codable, Equatable, Hashable, Identifiable, Sendable {
    case `default`
    case gradient1, gradient2, gradient3, gradient4
    case texture1, texture2
    case solid
    case custom(Data)

    var id: String {
        switch self {
        case .default: "default"
        case .gradient1: "gradient1"
        case .gradient2: "gradient2"
        case .gradient3: "gradient3"
        case .gradient4: "gradient4"
        case .texture1: "texture1"
        case .texture2: "texture2"
        case .solid: "solid"
        case .custom: "custom"
        }
    }

    var label: String {
        switch self {
        case .default: "Default"
        case .gradient1: "Sunset"
        case .gradient2: "Ocean"
        case .gradient3: "Forest"
        case .gradient4: "Aurora"
        case .texture1: "Paper"
        case .texture2: "Noise"
        case .solid: "Solid"
        case .custom: "Photo"
        }
    }
}

struct UserSettings: Codable, Hashable, Sendable {
    var userName: String
    var avatarInitials: String
    var notificationsEnabled: Bool
    var hapticFeedbackEnabled: Bool
    var environment: AppEnvironment
    var relayConfiguration: RelayConfiguration
    var autoConnectOnLaunch: Bool
    var locationSyncPreference: LocationSyncPreference
    var themePreset: ThemePreset
    var colorSchemePreference: ColorSchemePreference
    var chatWallpaper: ChatWallpaper
    var showAllDevices: Bool

    init(
        userName: String = "User",
        avatarInitials: String = "U",
        notificationsEnabled: Bool = true,
        hapticFeedbackEnabled: Bool = true,
        environment: AppEnvironment = AppEnvironmentPolicy.currentBuild.defaultEnvironment,
        relayConfiguration: RelayConfiguration = RelayConfiguration.defaultValue(),
        autoConnectOnLaunch: Bool = true,
        locationSyncPreference: LocationSyncPreference = .foregroundOnly,
        themePreset: ThemePreset = .nous,
        colorSchemePreference: ColorSchemePreference = .system,
        chatWallpaper: ChatWallpaper = .default,
        showAllDevices: Bool = false
    ) {
        self.userName = userName
        self.avatarInitials = avatarInitials
        self.notificationsEnabled = notificationsEnabled
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.environment = environment
        self.relayConfiguration = relayConfiguration
        self.autoConnectOnLaunch = autoConnectOnLaunch
        self.locationSyncPreference = locationSyncPreference
        self.themePreset = themePreset
        self.colorSchemePreference = colorSchemePreference
        self.chatWallpaper = chatWallpaper
        self.showAllDevices = showAllDevices
    }

    private enum CodingKeys: String, CodingKey {
        case userName
        case avatarInitials
        case notificationsEnabled
        case hapticFeedbackEnabled
        case environment
        case relayConfiguration
        case autoConnectOnLaunch
        case locationSyncPreference
        case themePreset
        case colorSchemePreference
        case chatWallpaper
        case showAllDevices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userName = try container.decodeIfPresent(String.self, forKey: .userName) ?? "User"
        avatarInitials = try container.decodeIfPresent(String.self, forKey: .avatarInitials) ?? "U"
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        hapticFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticFeedbackEnabled) ?? true
        environment = try container.decodeIfPresent(AppEnvironment.self, forKey: .environment) ?? AppEnvironmentPolicy.currentBuild.defaultEnvironment
        relayConfiguration = try container.decodeIfPresent(RelayConfiguration.self, forKey: .relayConfiguration)
            ?? RelayConfiguration.migratedLegacyValue(environment: environment)
        autoConnectOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? true
        locationSyncPreference = try container.decodeIfPresent(LocationSyncPreference.self, forKey: .locationSyncPreference) ?? .foregroundOnly
        themePreset = try container.decodeIfPresent(ThemePreset.self, forKey: .themePreset) ?? .nous
        colorSchemePreference = try container.decodeIfPresent(ColorSchemePreference.self, forKey: .colorSchemePreference) ?? .system
        chatWallpaper = try container.decodeIfPresent(ChatWallpaper.self, forKey: .chatWallpaper) ?? .default
        showAllDevices = try container.decodeIfPresent(Bool.self, forKey: .showAllDevices) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userName, forKey: .userName)
        try container.encode(avatarInitials, forKey: .avatarInitials)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(hapticFeedbackEnabled, forKey: .hapticFeedbackEnabled)
        try container.encode(environment, forKey: .environment)
        try container.encode(relayConfiguration, forKey: .relayConfiguration)
        try container.encode(autoConnectOnLaunch, forKey: .autoConnectOnLaunch)
        try container.encode(locationSyncPreference, forKey: .locationSyncPreference)
        try container.encode(themePreset, forKey: .themePreset)
        try container.encode(colorSchemePreference, forKey: .colorSchemePreference)
        try container.encode(chatWallpaper, forKey: .chatWallpaper)
        try container.encode(showAllDevices, forKey: .showAllDevices)
    }

    func applyingEnvironmentPolicy(
        _ policy: AppEnvironmentPolicy = .currentBuild,
        buildConfiguration: AppBuildConfiguration = .current()
    ) -> UserSettings {
        var sanitized = policy.sanitize(self)
        sanitized.relayConfiguration.applyBuildConfiguration(buildConfiguration)
        if sanitized.relayConfiguration.relayMode == .hosted, !sanitized.relayConfiguration.canUseHosted {
            sanitized.relayConfiguration.relayMode = .custom
        }
        return sanitized
    }
}

enum AppEnvironment: String, Codable, CaseIterable, Hashable, Sendable {
    case production
    case staging
    case development

    var displayLabel: String {
        switch self {
        case .production: "Production"
        case .staging: "Staging"
        case .development: "Development"
        }
    }

    var baseURLString: String {
        switch self {
        case .production: ""  // Use custom relay URL from RelayConfiguration
        case .staging: ""     // Use custom relay URL from RelayConfiguration
        case .development: "http://127.0.0.1:8000/v1"
        }
    }
}
