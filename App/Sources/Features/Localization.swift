import Foundation

@MainActor
enum AppLocalization {
    private static var overrideLanguageCode: String?

    static func setLanguage(_ language: AppLanguage) {
        overrideLanguageCode = language.bundleLanguageCode
    }

    static func localizedString(for key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static var localizedBundle: Bundle {
        guard let overrideLanguageCode,
              let path = Bundle.main.path(forResource: overrideLanguageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

extension String {
    @MainActor
    static func tr(_ key: String) -> String {
        AppLocalization.localizedString(for: key)
    }
}
