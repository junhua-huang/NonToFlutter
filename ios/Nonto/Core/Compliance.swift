import Foundation
import Combine
import CryptoKit

enum LegalDocument: String, CaseIterable, Identifiable {
    case privacy, terms, community
    var id: String { rawValue }
    var title: String {
        switch self { case .privacy: return "隐私政策"; case .terms: return "服务条款"; case .community: return "社区规范" }
    }
    var summary: String {
        switch self {
        case .privacy: return "了解账号、内容和推送信息如何处理，以及如何管理权限和申请删除。"
        case .terms: return "了解账号使用、内容权利、服务边界，以及举报和申诉方式。"
        case .community: return "尊重他人的隐私与交往意愿；发现骚扰、侵权或违法内容时，可以举报或屏蔽。"
        }
    }
}

enum SupportRequestKind: String, CaseIterable, Identifiable {
    case support, report, rights, appeal
    var id: String { rawValue }
    var title: String {
        switch self { case .support: return "使用反馈"; case .report: return "举报与侵权投诉"; case .rights: return "个人信息权利申请"; case .appeal: return "处置申诉" }
    }
    var guidance: String {
        switch self {
        case .support: return "请描述遇到的问题、出现步骤和期望结果。截图可在邮件中自行添加。"
        case .report: return "请提供内容链接或编号、涉及账号、发生时间及必要依据。侵权投诉请说明权利归属。"
        case .rights: return "请说明查阅、复制、更正、删除或撤回等具体请求、账号标识及数据范围。"
        case .appeal: return "请提供举报或处置编号、收到的处理结果，以及希望复核的事实和理由。"
        }
    }
    func message(detail: String) -> String {
        "南图 · \(title)\n\n\(detail.trimmingCharacters(in: .whitespacesAndNewlines))\n\n\(guidance)\n\n请勿发送密码、验证码、无关完整证件或他人的敏感信息。"
    }
}

struct ComplianceProfile {
    let values: [String: JSON]
    static let current: ComplianceProfile = {
        guard let url = Bundle.main.url(forResource: "Compliance", withExtension: "json"),
              let data = try? Data(contentsOf: url), let json = try? JSON.decode(data) else { return Self(values: [:]) }
        return Self(values: json.object)
    }()
    func value(_ key: String) -> String { values[key]?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    var websiteURL: URL { URL(string: "https://nonto.online/")! }
    var reviewed: Bool {
        values["releaseReviewed"] == .bool(true) &&
        (Bundle.main.object(forInfoDictionaryKey: "NontoDistributionChannel") as? String) != "testflight-internal"
    }
    var contactURL: URL? {
        let email = value("contactEmail")
        guard email.range(of: #"^[^\s@?:/]+@[^\s@?:/]+\.[^\s@?:/]+$"#, options: .regularExpression) != nil else { return nil }
        var components = URLComponents(); components.scheme = "mailto"; components.path = email
        return components.url
    }
    func requestMailURL(kind: SupportRequestKind, detail: String) -> URL? {
        guard let url = contactURL, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "subject", value: "南图 · \(kind.title)"),
                                 URLQueryItem(name: "body", value: kind.message(detail: detail))]
        return components.url
    }
    func httpsURL(_ key: String) -> URL? {
        guard let url = URL(string: value(key)), url.scheme == "https", url.host != nil, url.user == nil else { return nil }
        return url
    }
    func document(_ kind: String, bundle: Bundle = .main) -> String {
        guard LegalDocument(rawValue: kind) != nil, let url = bundle.url(forResource: kind, withExtension: "txt"),
              let template = try? String(contentsOf: url, encoding: .utf8) else { return "暂时无法读取说明，请稍后重试。" }
        return render(template)
    }
    func render(_ template: String) -> String {
        var text = template
        for key in ["policyVersion", "operatorName", "contactEmail", "contactAddress", "appFilingNumber", "storageSummary", "retentionSummary", "processorSummary", "minorProtectionSummary", "realNameVerificationSummary", "rightsResponseSummary"] {
            let replacement = value(key)
            let note = values["disclosureNotes"]?[key].string ?? ""
            text = text.replacingOccurrences(of: "{{\(key)}}", with: replacement.isEmpty ?
                (note.isEmpty ? "暂未提供。可通过“联系与投诉”了解相关信息。" : note) : replacement)
        }
        return text
    }
    static var revision: String {
        var data = Data()
        for (name, ext) in [("Compliance", "json")] + LegalDocument.allCases.map({ ($0.rawValue, "txt") }) {
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
