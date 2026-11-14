import Foundation

public enum L10n {
    public static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .module, value: key, comment: "")
    }
}
