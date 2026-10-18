import SwiftUI
import PhotosUI

struct ComicRecord: Record { var raw: JSON; init(_ raw: JSON) { self.raw = raw } }

struct ComicListView: View {
    @EnvironmentObject private var session: AppSession
    @State private var filter = "/comic/events"
    @State private var city = ""
    @State private var cities: [JSON] = []
    @State private var creating = false
    var body: some View {
        VStack {
            Picker("漫展范围", selection: $filter) { Text("全部").tag("/comic/events"); Text("已关注").tag("/comic/my-followed"); Text("我发布的").tag("/comic/my-events") }.pickerStyle(.segmented).padding(.horizontal)
            if filter == "/comic/events" {
                Picker("城市", selection: $city) { Text("全部城市").tag(""); ForEach(Array(cities.enumerated()), id: \.offset) { _, c in Text(c["name"].string).tag(c["name"].string) } }.padding(.horizontal)
            }
            ComicResults(session: session, path: filter, city: filter == "/comic/events" ? city : "").id(filter + city)
        }.navigationTitle("漫展").toolbar { Button { creating = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $creating) { ComicEditor() }
            .task { if let j = try? await session.api.request("/comic/cities") { cities = j.list("cities", "items") } }
    }
}
struct ComicResults: View {
    @StateObject private var resource: PagedResource<ComicRecord>
    init(session: AppSession, path: String, city: String) {
        _resource = StateObject(wrappedValue: PagedResource(api: session.api, path: path, keys: ["records", "events", "items"], query: ["city": city, "size": "20"], userID: session.user?.id ?? 0))
    }
    var body: some View {
        List {
            ForEach(resource.items) { event in
                RouteButton(.comic(event.id)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.raw["name"].string).font(.headline)
                        Text("\(event.raw["cityName"].string) · \(event.raw["venue"].string)").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(event.raw["startDate"].string) — \(event.raw["endDate"].string)").font(.caption).foregroundStyle(.secondary)
                        if !event.raw["coverImage"].string.isEmpty { AsyncImage(url: URL(string: event.raw["coverImage"].string)) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }.frame(height: 180).clipped().clipShape(RoundedRectangle(cornerRadius: 12)) }
                    }.padding(.vertical, 8)
                }
            }
            ResourceFooter(resource: resource)
        }.listStyle(.plain).task { await resource.loadIfNeeded() }.refreshable { await resource.load(reset: true) }
    }
}
struct ComicDetailView: View {
    let eventID: Int
    @EnvironmentObject private var session: AppSession
    @State private var event: JSON = .null
    @State private var comments: [Comment] = []
    @State private var error: String?
    @State private var text = ""
    @State private var busy = false
    @State private var editing = false
    @State private var page = 1
    @State private var more = false
    var body: some View {
        List {
            if !event.isNull {
                Section {
                    Text(event["name"].string).font(.title2.bold())
                    Text("\(event["cityName"].string) · \(event["venue"].string)").foregroundStyle(.secondary)
                    Text("\(event["startDate"].string) \(event["startTime"].string) — \(event["endDate"].string) \(event["endTime"].string)").font(.caption)
                    Text(event["intro"].string).textSelection(.enabled)
                    Text(event["ticketInfo"].string)
                    if let url = URL(string: event["website"].string), ["http", "https"].contains(url.scheme ?? "") { Link("活动网站", destination: url) }
                    MediaView(images: event["images"].array.map { $0["imageUrl"].string }.filter { !$0.isEmpty }, video: "")
                    Button(event["isFollowed"].or(event["is_following"]).bool ? "取消关注" : "关注漫展") { Task { await follow() } }.disabled(busy)
                }
                Section("评论") {
                    ForEach(comments) { c in VStack(alignment: .leading, spacing: 6) { Text(c.author.name).font(.caption.bold()); Text(c.content) } }
                    if more { Button("更多评论") { Task { await loadComments(append: true) } } }
                    TextField("发表一条评论…", text: $text, axis: .vertical)
                    Button("发送评论") { Task { await send() } }.disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            ErrorBanner(text: error)
        }.navigationTitle("漫展详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { if event["isOwner"].or(event["is_owner"]).bool { Button("编辑") { editing = true } } }
            .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) { ComicEditor(event: event) }
            .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do { event = try await session.api.request("/comic/events/\(eventID)", query: ["userId": String(session.user?.id ?? 0)]); error = nil; await loadComments() }
        catch { self.error = error.localizedDescription }
    }
    private func loadComments(append: Bool = false) async {
        do { let next = append ? page + 1 : 1; let j = try await session.api.request("/comic/events/\(eventID)/comments", query: ["page": String(next), "size": "20"]); let rows = j.list("comments", "records", "items").map(Comment.init); comments = Records.unique((append ? comments : []) + rows); page = next; more = rows.count >= 20 }
        catch { self.error = error.localizedDescription }
    }
    private func follow() async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/comic/events/\(eventID)/follow", method: "POST"); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func send() async {
        guard !busy else { return }
        let submittedText = text
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/comic/events/\(eventID)/comments", method: "POST", body: .object(["content": .text(text)])); if text == submittedText { text = "" }; await loadComments() }
        catch { self.error = error.localizedDescription }
    }
}
struct ComicEditor: View {
    var event: JSON = .null
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var venue = ""
    @State private var intro = ""
    @State private var ticket = ""
    @State private var website = ""
    @State private var cityID = 0
    @State private var cities: [JSON] = []
    @State private var start = Date()
    @State private var end = Date()
    @State private var picks: [PhotosPickerItem] = []
    @State private var error: String?
    @State private var busy = false
    @State private var tags: [JSON] = []
    @State private var selectedTags = Set<Int>()
    var body: some View {
        NavigationStack {
            Form {
                TextField("活动名称", text: $name)
                Picker("城市", selection: $cityID) { Text("请选择").tag(0); ForEach(Array(cities.enumerated()), id: \.offset) { _, c in Text(c["name"].string).tag(c["id"].int) } }
                TextField("场地地址", text: $venue)
                DatePicker("开始时间", selection: $start); DatePicker("结束时间", selection: $end, in: start...)
                TextField("活动介绍", text: $intro, axis: .vertical).lineLimit(3...10)
                TextField("票务信息", text: $ticket)
                TextField("活动网站", text: $website).keyboardType(.URL).textInputAutocapitalization(.never)
                Section("标签") { ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in Toggle(tag["name"].string, isOn: Binding(get: { selectedTags.contains(tag["id"].int) }, set: { if $0 { selectedTags.insert(tag["id"].int) } else { selectedTags.remove(tag["id"].int) } })) } }
                PhotosPicker(selection: $picks, maxSelectionCount: 9, matching: .images) { Label("活动图片（\(picks.count)）", systemImage: "photo") }
                ErrorBanner(text: error)
                if busy { ProgressView("正在保存…") }
            }.disabled(busy).navigationTitle(event.isNull ? "发布漫展" : "编辑漫展").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(busy || name.isEmpty || venue.isEmpty || cityID == 0) }
            }.interactiveDismissDisabled(busy).task {
                if !event.isNull {
                    name = event["name"].string; venue = event["venue"].string; intro = event["intro"].string; ticket = event["ticketInfo"].string; website = event["website"].string; cityID = event["cityId"].int
                    start = ServerDate.parse(.text(event["startDate"].string + "T" + (event["startTime"].string.isEmpty ? "00:00:00" : event["startTime"].string))) ?? Date()
                    end = ServerDate.parse(.text(event["endDate"].string + "T" + (event["endTime"].string.isEmpty ? "23:59:00" : event["endTime"].string))) ?? start
                }
                do {
                    let j = try await session.api.request("/comic/cities"); cities = j.list("cities", "items")
                    let t = try await session.api.request("/comic/tags"); tags = t.list("tags", "items")
                    let current = Set(event["tags"].array.map(\.string)); selectedTags = Set(tags.filter { current.contains($0["name"].string) }.map { $0["id"].int })
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            if !website.isEmpty { guard let u = URL(string: website), ["https", "http"].contains(u.scheme ?? ""), u.host != nil else { throw APIError(status: 0, message: "活动网站格式不正确") } }
            let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.timeZone = TimeZone(identifier: "Asia/Shanghai"); date.dateFormat = "yyyy-MM-dd"
            let time = DateFormatter(); time.locale = date.locale; time.timeZone = date.timeZone; time.dateFormat = "HH:mm"
            var urls = event["images"].array.map { $0["imageUrl"].string }.filter { !$0.isEmpty }
            for pick in picks { let m = try await MediaLoader.load(pick); urls.append(try await session.api.upload(m.data, filename: m.name, mime: m.mime, type: "comic")) }
            let body: JSON = .object(["name": .text(name), "cityId": .id(cityID), "venue": .text(venue),
                "start_date": .text(date.string(from: start)), "end_date": .text(date.string(from: max(start, end))),
                "start_time": .text(time.string(from: start)), "end_time": .text(time.string(from: max(start, end))),
                "intro": .text(intro), "ticket_info": .text(ticket), "website": .text(website),
                "tags": .array(tags.filter { selectedTags.contains($0["id"].int) }.map { $0["name"] }), "images": .array(urls.map(JSON.text)), "imageUrls": .array(urls.map(JSON.text))])
            _ = try await session.api.request(event.isNull ? "/comic/events" : "/comic/events/\(event["id"].int)", method: event.isNull ? "POST" : "PUT", body: body)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
