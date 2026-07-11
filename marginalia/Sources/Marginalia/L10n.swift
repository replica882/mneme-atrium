import Foundation

/// 轻量双语层（en/zh-Hans）。刻意不用 String Catalog——SPM 包内 Text 查表
/// 要每处加 bundle: .module，反而更重；功能文案两种语言就是全部需求。
/// 设计性手账微标签（words/review/tap to peel/know·slow·unknown…）不进这层，
/// 永远英文——那是设计语言不是 UI 文案。
public enum L10n {
    /// "system"（默认）/ "en" / "zh"
    public static let langKey = "marginaliaLang"

    public static var isChinese: Bool {
        switch UserDefaults.standard.string(forKey: langKey) {
        case "zh": return true
        case "en": return false
        default:   return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    /// 双语取值：t("English", "中文")。
    public static func t(_ en: String, _ zh: String) -> String {
        isChinese ? zh : en
    }
}

/// 全局便捷函数（调用处密集，短名减噪）。
@inlinable
public func t(_ en: String, _ zh: String) -> String {
    L10n.t(en, zh)
}
