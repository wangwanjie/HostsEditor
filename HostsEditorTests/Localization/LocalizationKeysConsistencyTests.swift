import Foundation
import Testing
@testable import HostsEditor

struct LocalizationKeysConsistencyTests {
    private func keys(for language: AppLanguage) throws -> Set<String> {
        let bundle = Bundle(for: AppDelegate.self)
        let path = try #require(bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language.rawValue))
        let dictionary = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        return Set(dictionary.keys)
    }

    @Test
    func allLanguagesDefineTheSameKeys() throws {
        let english = try keys(for: .english)
        let simplified = try keys(for: .simplifiedChinese)
        let traditional = try keys(for: .traditionalChinese)

        #expect(english.subtracting(simplified).isEmpty, "zh-Hans 缺少: \(english.subtracting(simplified).sorted())")
        #expect(simplified.subtracting(english).isEmpty, "en 缺少: \(simplified.subtracting(english).sorted())")
        #expect(english.subtracting(traditional).isEmpty, "zh-Hant 缺少: \(english.subtracting(traditional).sorted())")
        #expect(traditional.subtracting(english).isEmpty, "en 缺少: \(traditional.subtracting(english).sorted())")
    }

    @Test
    func formatPlaceholdersMatchAcrossLanguages() throws {
        let bundle = Bundle(for: AppDelegate.self)
        func table(_ language: AppLanguage) throws -> [String: String] {
            let path = try #require(bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language.rawValue))
            return try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        }
        func placeholders(_ value: String) -> [String] {
            let regex = try! NSRegularExpression(pattern: "%(?:@|ld|d|lu|f)")
            let range = NSRange(value.startIndex..., in: value)
            return regex.matches(in: value, range: range).compactMap { Range($0.range, in: value).map { String(value[$0]) } }
        }

        let english = try table(.english)
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese] {
            let localized = try table(language)
            for (key, value) in english {
                guard let other = localized[key] else {
                    continue
                }
                #expect(placeholders(value) == placeholders(other), "\(language.rawValue) 的 \(key) 占位符与英文不一致")
            }
        }
    }
}
