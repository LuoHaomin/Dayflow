import SwiftUI

struct SettingsOtherTabView: View {
  @ObservedObject var viewModel: OtherSettingsViewModel
  @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
  @AppStorage(DayflowAppearance.storageKey) private var appearance: DayflowAppearance = .system
  @FocusState private var isOutputLanguageFocused: Bool
  @State private var appLanguage = AppLanguagePreferences.selection()

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsStyle.sectionSpacing) {
      appPreferencesSection
      outputLanguageSection
      llmAdvancedSection
    }
  }

  // MARK: - Advanced LLM tuning (personal build)

  @State private var timeoutText: String = ""
  @State private var maxTokensText: String = ""
  @State private var minCardMinutesText: String = ""
  @State private var cliTimeoutText: String = ""

  private var llmAdvancedSection: some View {
    SettingsSection(
      title: String(localized: "Advanced LLM tuning"),
      subtitle: String(
        localized:
          "Timeouts are idle-intervals between network packets, not total request time. 0 restores defaults (600s / 16000 / 10min / 300s)."
      )
    ) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("Request timeout (seconds)")
            .font(.custom("Figtree", size: 13))
          Spacer()
          TextField("600", text: $timeoutText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            .onSubmit { saveAdvanced() }
        }
        HStack {
          Text("Max tokens (card generation)")
            .font(.custom("Figtree", size: 13))
          Spacer()
          TextField("16000", text: $maxTokensText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            .onSubmit { saveAdvanced() }
        }
        HStack {
          Text("Minimum card length (minutes)")
            .font(.custom("Figtree", size: 13))
          Spacer()
          TextField("10", text: $minCardMinutesText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            .onSubmit { saveAdvanced() }
        }
        HStack {
          Text("Agent CLI timeout (seconds)")
            .font(.custom("Figtree", size: 13))
          Spacer()
          TextField("300", text: $cliTimeoutText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            .onSubmit { saveAdvanced() }
        }
        SettingsSecondaryButton(title: String(localized: "Apply")) { saveAdvanced() }
      }
    }
    .onAppear {
      let d = UserDefaults.standard
      timeoutText = d.object(forKey: LLMAdvancedPreferences.requestTimeoutKey) == nil
        ? "" : String(Int(LLMAdvancedPreferences.requestTimeout))
      maxTokensText = d.object(forKey: LLMAdvancedPreferences.maxTokensKey) == nil
        ? "" : String(LLMAdvancedPreferences.maxTokens)
      minCardMinutesText = d.object(forKey: LLMAdvancedPreferences.minCardMinutesKey) == nil
        ? "" : String(LLMAdvancedPreferences.minCardMinutes)
      cliTimeoutText = d.object(forKey: LLMAdvancedPreferences.cliTimeoutKey) == nil
        ? "" : String(Int(LLMAdvancedPreferences.cliTimeout))
    }
  }

  private func saveAdvanced() {
    let d = UserDefaults.standard
    func setDouble(_ text: String, _ key: String) {
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      guard let value = Double(trimmed), value > 0 else {
        d.removeObject(forKey: key)
        return
      }
      d.set(value, forKey: key)
    }
    setDouble(timeoutText, LLMAdvancedPreferences.requestTimeoutKey)
    setDouble(maxTokensText, LLMAdvancedPreferences.maxTokensKey)
    setDouble(minCardMinutesText, LLMAdvancedPreferences.minCardMinutesKey)
    setDouble(cliTimeoutText, LLMAdvancedPreferences.cliTimeoutKey)
  }

  // MARK: - App preferences

  private var appPreferencesSection: some View {
    SettingsSection(
      title: String(localized: "App preferences"),
      subtitle: String(localized: "General toggles and telemetry settings.")
    ) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsRow(
          label: String(localized: "App language"),
          subtitle: String(
            localized:
              "Choose a language for Dayflow only. Quit and reopen the app to apply a change.")
        ) {
          Picker("App language", selection: $appLanguage) {
            ForEach(AppLanguage.allCases) { language in
              Text(verbatim: language.title).tag(language)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .frame(width: 210)
          .onChange(of: appLanguage) {
            AppLanguagePreferences.setSelection(appLanguage)
          }
        }

        SettingsRow(
          label: String(localized: "Light/Dark mode"),
          subtitle: String(localized: "Follow the system setting or pick light or dark.")
        ) {
          Picker("", selection: $appearance) {
            ForEach(DayflowAppearance.allCases) { option in
              Text(option.title).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 210)
          .onChange(of: appearance) { _, newValue in
            AnalyticsService.shared.capture(
              "appearance_changed", ["appearance": newValue.rawValue])
          }
        }

        SettingsRow(
          label: String(localized: "Launch Dayflow at login"),
          subtitle:
            String(
              localized:
                "Keeps the menu bar controller running right after you sign in so capture can resume instantly."
            )
        ) {
          SettingsToggle(
            isOn: Binding(
              get: { launchAtLoginManager.isEnabled },
              set: { launchAtLoginManager.setEnabled($0) }
            )
          )
        }

        SettingsRow(label: String(localized: "Share crash reports and anonymous usage data")) {
          SettingsToggle(isOn: $viewModel.analyticsEnabled)
        }

        SettingsRow(
          label: String(localized: "Show Dock icon"),
          subtitle: String(localized: "When off, Dayflow runs as a menu bar-only app.")
        ) {
          SettingsToggle(isOn: $viewModel.showDockIcon)
        }

        SettingsRow(
          label: String(localized: "Show app/website icons in timeline"),
          subtitle: String(localized: "When off, timeline cards won't show app or website icons.")
        ) {
          SettingsToggle(isOn: $viewModel.showTimelineAppIcons)
        }

        SettingsRow(
          label: String(localized: "Show daily goal popups"),
          subtitle:
            String(
              localized:
                "When off, Dayflow won't automatically open goal setup or yesterday's review after 4am."
            )
        ) {
          SettingsToggle(isOn: $viewModel.showDailyGoalPopups)
        }

        SettingsRow(
          label: String(localized: "Save all timelapses to disk"),
          subtitle:
            String(
              localized:
                "New and reprocessed timeline cards will pre-generate timelapse videos and store them on disk instead of building them on demand. Uses more storage and background processing."
            ),
          showsDivider: false
        ) {
          SettingsToggle(isOn: $viewModel.saveAllTimelapsesToDisk)
        }
      }
    }
  }

  // MARK: - Output language override

  private var outputLanguageSection: some View {
    SettingsSection(
      title: String(localized: "Output language override"),
      subtitle:
        String(
          localized:
            "AI output follows the app language by default. Enter a language to override it, or reset to follow the app language. Existing summaries stay unchanged."
        )
    ) {
      HStack(spacing: 10) {
        TextField("App language", text: $viewModel.outputLanguageOverride)
          .textFieldStyle(.roundedBorder)
          .disableAutocorrection(true)
          .frame(maxWidth: 220)
          .focused($isOutputLanguageFocused)
          .onChange(of: viewModel.outputLanguageOverride) {
            viewModel.markOutputLanguageOverrideEdited()
          }

        SettingsSecondaryButton(
          title: viewModel.isOutputLanguageOverrideSaved
            ? String(localized: "Saved") : String(localized: "Save"),
          systemImage: viewModel.isOutputLanguageOverrideSaved
            ? "checkmark" : nil,
          isDisabled: viewModel.isOutputLanguageOverrideSaved,
          action: {
            viewModel.saveOutputLanguageOverride()
            isOutputLanguageFocused = false
          }
        )

        SettingsSecondaryButton(
          title: String(localized: "Reset"),
          action: {
            viewModel.resetOutputLanguageOverride()
            isOutputLanguageFocused = false
          }
        )

        Spacer()
      }
    }
  }
}
