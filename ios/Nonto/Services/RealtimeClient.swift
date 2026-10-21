import Foundation
import Combine

/// Native implementation of packages/reliable_websocket's v1 envelope.
/// HTTP is authoritative for chat history and idempotent sends.
@MainActor
final class RealtimeClient: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var revision = 0
    let events = PassthroughSubject<JSON, Never>()
    private let api: APIClient
    private var loop: Task<Void, Never>?
    private var connection: URLSessionWebSocketTask?
    private var rooms = Set<Int>()
    private var userID = 0
    private var token: String?
    private var runID = UUID()
    private var lastFrame = Date.distantPast
    var onLiveEvent: ((JSON, Int) -> Void)?
    private var sequenceKey: String { "nonto.native.sequence.\(userID)" }

    init(api: APIClient) { self.api = api }
    func start(userID: Int) {
        guard userID > 0, let token = api.token else { stop(); return }
        if self.userID == userID, self.token == token, loop != nil { return }
        if self.userID != userID { resetRooms() }
        stop(); self.userID = userID; self.token = token
        let ticket = UUID(); runID = ticket
        loop = Task { [weak self] in
            guard let self else { return }
            var attempt = 0
            while !Task.isCancelled, runID == ticket, api.token != nil {
                do { try await connect(ticket: ticket); attempt = 0 }
                catch { if runID == ticket { connected = false } }
                guard !Task.isCancelled, runID == ticket else { break }
                attempt += 1
                try? await Task.sleep(for: .seconds(min(30, pow(2, Double(min(attempt, 5))))))
            }
        }
    }
    func stop() {
        runID = UUID(); loop?.cancel(); loop = nil
        connection?.cancel(with: .goingAway, reason: nil); connection = nil; connected = false
    }
    func resetRooms() { rooms.removeAll() }
    func room(_ id: Int, joined: Bool) {
        guard id > 0 else { return }
        let changed = joined ? rooms.insert(id).inserted : rooms.remove(id) != nil
        guard changed, connected, let socket = connection else { return }
        let ticket = runID
        Task { try? await send(joined ? "join" : "leave", ["conversation_id": .id(id)], socket: socket, ticket: ticket) }
    }
    private func send(_ type: String, _ payload: [String: JSON] = [:], socket: URLSessionWebSocketTask, ticket: UUID) async throws {
        guard ticket == runID, connection === socket else { throw CancellationError() }
        let json = JSON.object(["type": .text(type), "payload": .object(payload)])
        try await socket.send(.string(String(decoding: try json.encoded(), as: UTF8.self)))
    }
    static func connectionURL(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "wss", components.host != nil, components.user == nil else { throw URLError(.badURL) }
        let query = (components.queryItems ?? []).filter { $0.name != "access_token" }
        components.queryItems = query.isEmpty ? nil : query
        guard let result = components.url else { throw URLError(.badURL) }
        return result
    }
    private func connect(ticket: UUID) async throws {
        guard let token = api.token else { return }
        let url = try Self.connectionURL(api.socketURL)
        let socket = URLSession.shared.webSocketTask(with: url); connection = socket; socket.resume()
        lastFrame = Date()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        try await send("auth", ["token": .text(token)], socket: socket, ticket: ticket)
        let heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(20))
                    guard let self, self.runID == ticket else { return }
                    guard Date().timeIntervalSince(self.lastFrame) < 70 else {
                        socket.cancel(with: .goingAway, reason: nil); return
                    }
                    try await self.send("ping", socket: socket, ticket: ticket)
                } catch { socket.cancel(with: .goingAway, reason: nil); return }
            }
        }
        defer { heartbeat.cancel() }
        while !Task.isCancelled, runID == ticket {
            let message = try await socket.receive()
            guard runID == ticket else { return }
            let data: Data
            switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
            lastFrame = Date()
            let frame = try JSON.decode(data), payload = frame["payload"].or(frame)
            switch frame["type"].string {
            case "auth_result":
                guard payload["success"].bool else { throw APIError(status: 401, message: "实时连接认证失败") }
                connected = true; revision += 1
                events.send(.object(["event": .text("resync")]))
                try await send("sync", ["last_received_seq": .id(UserDefaults.standard.integer(forKey: sequenceKey)), "limit": .id(200)], socket: socket, ticket: ticket)
                for id in rooms { try await send("join", ["conversation_id": .id(id)], socket: socket, ticket: ticket) }
            case "message": try await receive(frame, live: true, socket: socket, ticket: ticket)
            case "sync_result":
                let before = UserDefaults.standard.integer(forKey: sequenceKey)
                let frames = payload["list"].or(payload["messages"]).array.sorted { $0["seq"].int < $1["seq"].int }
                for item in frames { try await receive(item, socket: socket, ticket: ticket) }
                let current = UserDefaults.standard.integer(forKey: sequenceKey)
                let maximum = payload["current_max_seq"].int
                if payload["has_more"].bool {
                    guard current > before else { throw URLError(.badServerResponse) }
                    try await send("sync", ["last_received_seq": .id(current), "limit": .id(200)], socket: socket, ticket: ticket)
                } else if maximum > current { UserDefaults.standard.set(maximum, forKey: sequenceKey) }
                revision += 1
                if !payload["has_more"].bool { events.send(.object(["event": .text("resync")])) }
            default: break
            }
        }
    }
    private func receive(_ frame: JSON, live: Bool = false, socket: URLSessionWebSocketTask, ticket: UUID) async throws {
        guard ticket == runID else { throw CancellationError() }
        let seq = frame["seq"].int, previous = UserDefaults.standard.integer(forKey: sequenceKey)
        if live && (seq == 0 || seq > previous) { onLiveEvent?(frame["payload"].or(frame), seq) }
        let payload = frame["payload"].or(frame), event = payload["event"].string
        if (seq == 0 || seq > previous) && !["typing", "stop_typing"].contains(event) {
            revision += 1; events.send(payload)
        }
        if seq > previous { UserDefaults.standard.set(seq, forKey: sequenceKey) }
        if seq > 0 { try await send("ack_receive", ["seq": .id(seq)], socket: socket, ticket: ticket) }
    }
}
