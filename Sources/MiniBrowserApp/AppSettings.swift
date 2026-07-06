import Foundation
import MiniBrowserCore

/// App-wide persisted settings: global color inversion, ad blocking, boss mode.
/// Loads once from settings.json at launch and saves immediately on every change.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// True when settings.json existed at launch — gates the one-time migration
    /// that inherits the old per-tab inversion from the session.
    let loadedFromDisk: Bool

    /// Registered by TabsModel so a global inversion change reaches every tab.
    var onInvertedChange: ((Bool) -> Void)?

    @Published var inverted: Bool {
        didSet {
            guard oldValue != inverted else { return }
            save()
            onInvertedChange?(inverted)
        }
    }
    @Published var adBlockEnabled: Bool {
        didSet { if oldValue != adBlockEnabled { save() } }
    }
    @Published var bossModeEnabled: Bool {
        didSet { if oldValue != bossModeEnabled { save() } }
    }

    private let store = SettingsStore(directory: AppPaths.supportDirectory())

    private init() {
        loadedFromDisk = store.fileExists
        let s = store.load()
        inverted = s.inverted
        adBlockEnabled = s.adBlockEnabled
        bossModeEnabled = s.bossModeEnabled
    }

    /// First run without a settings file: inherit the session's inversion so the
    /// user's existing tabs keep looking the same after the per-tab -> global switch.
    func migrateInvertedIfNeeded(fromSession sessionInverted: Bool) {
        guard !loadedFromDisk else { return }
        inverted = sessionInverted   // didSet persists + propagates (no-op if equal)
    }

    private func save() {
        store.save(Settings(inverted: inverted,
                            adBlockEnabled: adBlockEnabled,
                            bossModeEnabled: bossModeEnabled))
    }
}
