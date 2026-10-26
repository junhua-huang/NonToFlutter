from pathlib import Path
import json

root = Path(__file__).resolve().parents[1] if Path(__file__).parent.name == 'scripts' else Path('/workspace/scratch/8599392464ce/nonto-menu/ios')
source = root / 'Nonto'
snapshot_path = root.parent / '.github/appstore/capture/public_content_snapshot.json'
snapshot = snapshot_path.read_text()
app = source / 'NontoApp.swift'
text = app.read_text().replace('@main\n', '')
text = text.replace('.tabViewStyle(.sidebarAdaptable)', '''.onReceive(StoreCaptureDriver.shared.$command) { command in
            switch command {
            case "profile": selectedTab = 4
            case "feed": selectedTab = 0
            case "compose": compose = true
            case "close-compose": compose = false
            default: break
            }
        }
        .tabViewStyle(.sidebarAdaptable)''')
text = text.replace('{ PostComposer() }', '{ PostComposer(editor: StoreCaptureDriver.shared.editor, initialMedia: StoreCaptureDriver.shared.media) }')
app.write_text(text)

nav = source / 'Views/AppNavigation.swift'
text = nav.read_text().replace('}.environment(\\.navigate, navigation.open)', '''}.environment(\\.navigate, navigation.open)
        .onReceive(StoreCaptureDriver.shared.$command) { command in
            if command == "back" { navigation.path = [] }
        }''')
nav.write_text(text)
feed = source / 'Views/FeedViews.swift'
text = feed.read_text().replace('@Environment(\\.openComposer) private var compose', '@Environment(\\.openComposer) private var compose\n    @Environment(\\.navigate) private var captureNavigate', 1)
text = text.replace('.navigationTitle("南图").navigationBarTitleDisplayMode(.inline)', '''.navigationTitle("南图").navigationBarTitleDisplayMode(.inline)
        .onReceive(StoreCaptureDriver.shared.$command) { command in
            if command == "post" { captureNavigate(.post(214, initial: StoreCaptureDriver.shared.featured)) }
        }''', 1)
feed.write_text(text)
harness = r'''import SwiftUI
import UIKit
import Combine

// Capture-only entry point generated in CI. Production views are reused unchanged
// except for navigation/scroll command hooks. Public server responses are replayed;
// credentials, private messages and any remote writes are deliberately unavailable.
@main @MainActor struct StoreCaptureApp: App {
    @StateObject private var driver = StoreCaptureDriver.shared
    var body: some Scene {
        WindowGroup {
            Group {
                if driver.ready { MainTabs() }
                else { ProgressView("正在准备作品…") }
            }
            .environmentObject(driver.session)
            .environmentObject(PrivacyConsent.shared)
            .environment(\.appAccent, AppAccent.blue).tint(AppAccent.blue.color)
            .preferredColorScheme(driver.dark ? .dark : .light)
            .fullScreenCover(isPresented: $driver.gallery) {
                ImageGallery(images: driver.featured.images, initial: 0)
            }
            .task { await driver.prepareAndListen() }
        }
    }
}

private struct CaptureCredentials: CredentialStore {
    func read() throws -> String? { nil }
    func write(_ token: String?) throws {}
}

final class CaptureReplay: URLProtocol, @unchecked Sendable {
    static let snapshot = try! JSON.decode(Data(snapshotText.utf8))
    static let snapshotText = #"""
__SNAPSHOT__
"""#
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let snapshot = Self.snapshot
        let feed = snapshot["feed"].array
        let own = snapshot["own"].array
        let response: JSON
        if request.httpMethod != "GET" {
            client?.urlProtocol(self, didFailWithError: URLError(.noPermissionsToReadFile)); return
        } else if path.hasSuffix("/auth/profile") || path.contains("/auth/users/") { response = snapshot["profile"] }
        else if path.contains("/posts/user/") { response = .object(["posts": .array(own), "has_more": .bool(false)]) }
        else if path.hasSuffix("/posts/") || path.contains("/recommendations/feed") {
            response = .object(["posts": .array(feed.sorted { $0["id"].int == 214 && $1["id"].int != 214 }), "has_more": .bool(false)])
        } else if path.hasSuffix("/comments") { response = .object(["comments": .array([]), "has_more": .bool(false)]) }
        else if let id = Int(path.split(separator: "/").last ?? ""), let post = (feed + own).first(where: { $0["id"].int == id }) { response = .object(["post": post]) }
        else { response = .object(["unread_count": .id(0)]) }
        let data = try! response.encoded()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class StoreCaptureDriver: ObservableObject {
    static let shared = StoreCaptureDriver()
    let session: AppSession
    let editor = ComposerEditor()
    let featured: Post
    var media: [SelectedMedia] = []
    @Published var ready = false
    @Published var dark = false
    @Published var gallery = false
    @Published var command = ""
    private var listening = false
    private let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CaptureReplay.self]
        let api = APIClient(baseURL: URL(string: "https://store-capture.example.test/api")!, session: URLSession(configuration: config), credentials: CaptureCredentials())
        session = AppSession(api: api)
        session.user = Person(CaptureReplay.snapshot["profile"])
        session.restoring = false
        featured = Post(CaptureReplay.snapshot["feed"].array.first { $0["id"].int == 214 }!)
        editor.replaceText("记录此刻的热爱 #二次元")
    }
    func prepareAndListen() async {
        guard !listening else { return }; listening = true
        do {
            let snapshot = CaptureReplay.snapshot
            var urls = Set<String>()
            for item in snapshot["feed"].array + snapshot["own"].array {
                urls.formUnion(Post(item).images)
                if !Post(item).author.avatar.isEmpty { urls.insert(Post(item).author.avatar) }
            }
            let person = Person(snapshot["profile"])
            if !person.avatar.isEmpty { urls.insert(person.avatar) }
            if !person.cover.isEmpty { urls.insert(person.cover) }
            for url in urls.sorted() {
                let image = try await ImageRepository.shared.image(at: url, maxPixelSize: 1600)
                ImageRepository.shared.rememberUploadedPreview(image, at: url)
                if featured.images.contains(url), let data = image.jpegData(compressionQuality: 0.92) { media.append(try SelectedMedia.image(data)) }
            }
            ready = true
            try await Task.sleep(for: .seconds(3))
            try Data("ready".utf8).write(to: folder.appendingPathComponent("capture-ready.txt"), options: .atomic)
        } catch {
            try? Data(error.localizedDescription.utf8).write(to: folder.appendingPathComponent("capture-error.txt"), options: .atomic)
            return
        }
        var last = ""
        while !Task.isCancelled {
            if let value = try? String(contentsOf: folder.appendingPathComponent("capture-command.txt"), encoding: .utf8), value != last {
                last = value
                let action = value.split(separator: "|").last.map(String.init) ?? value
                if action == "dark" { withAnimation(.smooth) { dark = true } }
                else if action == "light" { withAnimation(.smooth) { dark = false } }
                else if action == "gallery" { gallery = true }
                else if action == "close-gallery" { gallery = false }
                else if action == "scroll" { scroll(by: 280) }
                else { command = action }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    private func scroll(by distance: CGFloat) {
        func find(_ view: UIView) -> [UIScrollView] {
            guard !view.isHidden, view.alpha > 0.01 else { return [] }
            return (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(find)
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        let candidates = windows.filter(\.isKeyWindow).flatMap { find($0) }.filter {
            $0.bounds.height > 300 && $0.contentSize.height > $0.bounds.height
        }
        guard let scroll = candidates.max(by: { $0.bounds.height < $1.bounds.height }) else { return }
        let maxY = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let y = min(maxY, scroll.contentOffset.y + distance)
        UIView.animate(withDuration: 1.25, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            scroll.contentOffset = CGPoint(x: scroll.contentOffset.x, y: y)
            scroll.layoutIfNeeded()
        }
    }
}
'''.replace('__SNAPSHOT__', snapshot)
(source / 'StoreCaptureApp.swift').write_text(harness)
print('Prepared capture-only entry point and command hooks; no XCTest or remote writes.')
