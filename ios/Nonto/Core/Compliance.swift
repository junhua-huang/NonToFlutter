import Foundation
import Combine
import CryptoKit

struct ComplianceProfile {
    let values: [String: JSON]
    static let current: ComplianceProfile = {
        guard let url = Bundle.main.url(forResource: "Compliance", withExtension: "json"),
              let data = try? Data(contentsOf: url), let json = try? JSON.decode(data) else { return Self(values: [:]) }
        return Self(values: json.object)
    }()
    func value(_ key: String) -> String { values[key]?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    var reviewed: Bool {
        values["releaseReviewed"] == .bool(true) &&
        (Bundle.main.object(forInfoDictionaryKey: "NontoDistributionChannel") as? String) != "testflight-internal"
    }
    var contactURL: URL? {
        let email = value("contactEmail")
        guard email.contains("@"), !email.contains(where: { $0.isWhitespace }), !email.contains("?") else { return nil }
        var components = URLComponents(); components.scheme = "mailto"; components.path = email
        return components.url
    }
    func httpsURL(_ key: String) -> URL? {
        guard let url = URL(string: value(key)), url.scheme == "https", url.host != nil, url.user == nil else { return nil }
        return url
    }
    func document(_ kind: String, bundle: Bundle = .main) -> String {
        guard ["privacy", "terms"].contains(kind), let url = bundle.url(forResource: kind, withExtension: "txt"),
              let template = try? String(contentsOf: url, encoding: .utf8) else { return "暂时无法读取说明，请稍后重试。" }
        return render(template)
    }
    func render(_ template: String) -> String {
        var text = template
        for key in ["policyVersion", "operatorName", "contactEmail", "contactAddress", "appFilingNumber", "storageSummary", "retentionSummary", "processorSummary", "minorProtectionSummary", "realNameVerificationSummary", "rightsResponseSummary"] {
            let replacement = value(key)
            text = text.replacingOccurrences(of: "{{\(key)}}", with: replacement.isEmpty ? "该项尚未完成核验，当前仅供开发测试。" : replacement)
        }
        return reviewed ? text : "开发测试版说明：服务规则尚未完成审核，本说明不能作为正式发布政策。请勿提交真实敏感个人信息。\n\n" + text
    }
    static var revision: String {
        var data = Data()
        for (name, ext) in [("Compliance", "json"), ("privacy", "txt"), ("terms", "txt")] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext), let contents = try? Data(contentsOf: url) { data.append(contents) }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct PolicySection: Identifiable {
    let id: Int
    let title: String
    var paragraphs: [String]

    static func parse(_ text: String) -> [PolicySection] {
        var sections: [PolicySection] = []
        for block in text.components(separatedBy: "\n\n") {
            let paragraph = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraph.isEmpty else { continue }
            if paragraph.range(of: "^[一二三四五六七八九十百]+、[^\\n]+$", options: .regularExpression) != nil {
                sections.append(Self(id: sections.count, title: paragraph, paragraphs: []))
            } else {
                if sections.isEmpty { sections.append(Self(id: 0, title: "阅读提示", paragraphs: [])) }
                sections[sections.count - 1].paragraphs.append(paragraph)
            }
        }
        return sections
    }
}

/// Only explicit acceptance opens authenticated screens and starts session restoration.
@MainActor
final class PrivacyConsent: ObservableObject {
    static let shared = PrivacyConsent()
    @Published private(set) var accepted: Bool
    private let defaults: UserDefaults
    private let revision: String
    private let key = "nonto.native.privacy-consent"
    init(defaults: UserDefaults = .standard, revision: String = ComplianceProfile.revision) {
        self.defaults = defaults; self.revision = revision
        accepted = defaults.string(forKey: key) == revision
    }
    func accept() {
        defaults.set(revision, forKey: key); defaults.set(Date(), forKey: key + ".date"); accepted = true
    }
    func revoke() {
        defaults.removeObject(forKey: key); defaults.removeObject(forKey: key + ".date"); accepted = false
    }
}

@MainActor
enum AccountLocalData {
    static func clear(userID: Int, defaults: UserDefaults = .standard) throws {
        guard userID > 0 else { return }
        let prefixes = ["nonto.native.draft.\(userID).", "nonto.native.outbox.\(userID).", "nonto.native.chat-draft.\(userID)."]
        for key in defaults.dictionaryRepresentation().keys {
            if prefixes.contains(where: { key.hasPrefix($0) }) || key == "nonto.native.sequence.\(userID)" { defaults.removeObject(forKey: key) }
        }
        URLCache.shared.removeAllCachedResponses()
        try LocalCache.clear(userID: userID)
    }
}
