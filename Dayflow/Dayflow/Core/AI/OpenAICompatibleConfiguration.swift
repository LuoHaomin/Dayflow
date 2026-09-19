import Foundation

enum OpenAICompatiblePreset: String, Codable, CaseIterable {
  case openRouter = "openrouter"
  case custom
}

struct OpenAICompatibleConfiguration: Codable, Equatable {
  static let openRouterBaseURL = "https://openrouter.ai/api/v1"

  let preset: OpenAICompatiblePreset
  let baseURL: String
  let modelID: String

  init(preset: OpenAICompatiblePreset, baseURL: String, modelID: String) {
    self.preset = preset
    self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    self.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func openRouter(modelID: String = "") -> OpenAICompatibleConfiguration {
    OpenAICompatibleConfiguration(
      preset: .openRouter,
      baseURL: openRouterBaseURL,
      modelID: modelID
    )
  }

  var chatCompletionsURL: URL? {
    LocalEndpointUtilities.chatCompletionsURL(baseURL: baseURL)
  }

  var isComplete: Bool {
    !baseURL.isEmpty && !modelID.isEmpty && chatCompletionsURL != nil
  }
}

enum OpenAICompatiblePreferences {
  static let keychainProvider = "openai_compatible"
  private static let configurationKey = "llmOpenAICompatibleConfigurationV1"

  static func load(from defaults: UserDefaults = .standard) -> OpenAICompatibleConfiguration? {
    guard let data = defaults.data(forKey: configurationKey) else { return nil }
    return try? JSONDecoder().decode(OpenAICompatibleConfiguration.self, from: data)
  }

  @discardableResult
  static func save(
    _ configuration: OpenAICompatibleConfiguration,
    to defaults: UserDefaults = .standard
  ) -> Bool {
    guard let data = try? JSONEncoder().encode(configuration) else { return false }
    let previousValue = defaults.object(forKey: configurationKey)
    defaults.set(data, forKey: configurationKey)
    guard load(from: defaults) == configuration else {
      if let previousValue {
        defaults.set(previousValue, forKey: configurationKey)
      } else {
        defaults.removeObject(forKey: configurationKey)
      }
      return false
    }
    return true
  }

  static func reset(in defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: configurationKey)
  }
}

struct OpenAICompatibleRuntimeConfiguration: Sendable {
  let endpoint: String
  let modelID: String
  let bearerToken: String?
  let analyticsProvider: String
  /// "auto" keeps the MiniMax-M3 heuristic; "disabled"/"adaptive" force the
  /// MiniMax thinking parameter for every request.
  let thinkingMode: String

  init(
    configuration: OpenAICompatibleConfiguration,
    bearerToken: String?,
    analyticsProvider: String = OpenAICompatiblePreferences.keychainProvider,
    thinkingMode: String = "auto"
  ) {
    endpoint = configuration.baseURL
    modelID = configuration.modelID

    let trimmedToken = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.bearerToken = trimmedToken.isEmpty ? nil : trimmedToken

    let trimmedProvider = analyticsProvider.trimmingCharacters(in: .whitespacesAndNewlines)
    self.analyticsProvider =
      trimmedProvider.isEmpty
      ? OpenAICompatiblePreferences.keychainProvider
      : trimmedProvider
    self.thinkingMode = thinkingMode
  }
}

// MARK: - Multi-provider profiles (personal build)

/// A user-defined OpenAI-compatible provider. Built-in entries (OpenRouter,
/// MiniMax, ...) act only as templates; every profile is editable and
/// deletable. API keys are stored per-profile in the keychain.
struct ProviderProfile: Codable, Equatable, Identifiable {
  var id: UUID = UUID()
  var name: String
  var baseURL: String
  var modelID: String
  /// "auto" (MiniMax-M3 heuristic), "disabled", or "adaptive".
  var thinkingMode: String = "auto"

  var configuration: OpenAICompatibleConfiguration {
    OpenAICompatibleConfiguration(preset: .custom, baseURL: baseURL, modelID: modelID)
  }

  var isComplete: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && configuration.isComplete
  }

  static let templates: [ProviderProfile] = [
    ProviderProfile(
      name: "OpenRouter", baseURL: OpenAICompatibleConfiguration.openRouterBaseURL,
      modelID: ""),
    ProviderProfile(name: "MiniMax", baseURL: "https://api.minimax.cn/v1", modelID: "MiniMax-M3"),
    ProviderProfile(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", modelID: ""),
    ProviderProfile(
      name: "Gemini (OpenAI-compat)", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
      modelID: ""),
  ]
}

enum ProviderProfileStore {
  private static let listKey = "llmProviderProfilesV1"
  private static let selectedKey = "llmProviderProfilesSelectedV1"

  static func keychainID(for profileID: UUID) -> String {
    "openai_compatible_\(profileID.uuidString)"
  }

  static func load(from defaults: UserDefaults = .standard) -> [ProviderProfile] {
    if let data = defaults.data(forKey: listKey),
      let profiles = try? JSONDecoder().decode([ProviderProfile].self, from: data)
    {
      if !profiles.isEmpty { return profiles }
    }
    // Migrate the legacy single configuration (if any) into the first profile.
    if let legacy = OpenAICompatiblePreferences.load(from: defaults), legacy.isComplete {
      let profile = ProviderProfile(
        name: legacy.preset == .openRouter ? "OpenRouter" : "Custom API",
        baseURL: legacy.baseURL, modelID: legacy.modelID)
      if let oldKey = KeychainManager.shared.retrieve(
        for: OpenAICompatiblePreferences.keychainProvider), !oldKey.isEmpty
      {
        KeychainManager.shared.store(oldKey, for: keychainID(for: profile.id))
      }
      save([profile], to: defaults)
      select(profile.id, in: defaults)
      return [profile]
    }
    return []
  }

  @discardableResult
  static func save(_ profiles: [ProviderProfile], to defaults: UserDefaults = .standard) -> Bool {
    guard let data = try? JSONEncoder().encode(profiles) else { return false }
    defaults.set(data, forKey: listKey)
    return true
  }

  static func selectedID(from defaults: UserDefaults = .standard) -> UUID? {
    if let raw = defaults.string(forKey: selectedKey), let id = UUID(uuidString: raw) {
      return id
    }
    return nil
  }

  static func select(_ id: UUID, in defaults: UserDefaults = .standard) {
    defaults.set(id.uuidString, forKey: selectedKey)
  }

  /// The profile the LLM pipeline should use, or nil when none is configured.
  static func selectedProfile(from defaults: UserDefaults = .standard) -> ProviderProfile? {
    let profiles = load(from: defaults)
    guard let id = selectedID(from: defaults) else {
      return profiles.first(where: \.isComplete)
    }
    if let match = profiles.first(where: { $0.id == id }), match.isComplete {
      return match
    }
    return profiles.first(where: \.isComplete)
  }

  static func apiKey(for profile: ProviderProfile) -> String? {
    KeychainManager.shared.retrieve(for: keychainID(for: profile.id))
  }

  @discardableResult
  static func upsert(_ profile: ProviderProfile, to defaults: UserDefaults = .standard) -> Bool {
    var profiles = load(from: defaults)
    if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
      profiles[index] = profile
    } else {
      profiles.append(profile)
    }
    let ok = save(profiles, to: defaults)
    if selectedID(from: defaults) == nil { select(profile.id, in: defaults) }
    return ok
  }

  @discardableResult
  static func delete(_ id: UUID, in defaults: UserDefaults = .standard) -> Bool {
    var profiles = load(from: defaults)
    guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
    let removed = profiles.remove(at: index)
    _ = KeychainManager.shared.delete(for: keychainID(for: removed.id))
    let ok = save(profiles, to: defaults)
    if selectedID(from: defaults) == id {
      if let first = profiles.first { select(first.id, in: defaults) }
      else { defaults.removeObject(forKey: selectedKey) }
    }
    return ok
  }
}

/// Runtime-tunable knobs that were previously hardcoded. Defaults match the
/// values used by the patched personal build.
enum LLMAdvancedPreferences {
  static let requestTimeoutKey = "llmAdvancedRequestTimeoutSeconds"
  static let maxTokensKey = "llmAdvancedMaxTokens"
  static let minCardMinutesKey = "llmAdvancedMinCardMinutes"
  static let cliTimeoutKey = "llmAdvancedCLITimeoutSeconds"

  static var requestTimeout: TimeInterval {
    let v = UserDefaults.standard.double(forKey: requestTimeoutKey)
    return v > 0 ? v : 600
  }

  static var maxTokens: Int {
    let v = UserDefaults.standard.integer(forKey: maxTokensKey)
    return v > 0 ? v : 16000
  }

  static var minCardMinutes: Double {
    let v = UserDefaults.standard.double(forKey: minCardMinutesKey)
    return v > 0 ? v : 10
  }

  static var cliTimeout: TimeInterval {
    let v = UserDefaults.standard.double(forKey: cliTimeoutKey)
    return v > 0 ? v : 300
  }
}
