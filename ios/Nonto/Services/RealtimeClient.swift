import Foundation
import Combine

/// Native implementation of packages/reliable_websocket's v1 envelope.
/// HTTP is authoritative for chat history and idempotent sends.
@MainActor
final class RealtimeClient: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var revision = 0
    private let api: APIClient
    private var loop: Task<Void, Never>?
    private var connection: URLSessionWebSocketTask?
    private var rooms = Set<Int>()
    private var userID = 0
    private var runID = UUID()
    private var lastFrame = Date.distantPast
    var onLiveEvent: ((JSON, Int) -> Void)?
    private var sequenceKey: String { "nonto.native.sequence.\(userID)" }

    init(api: APIClient) { self.api = api }
    func start(userID: Int) {
        stop(); self.userID = userID
        let ticket = UUID(); runID = ticket
        loop = Task { [weak self] in
            guard let self else { return }
            var attempt = 0
            while !Task.isCancelled, runID == ticket, api.token != nil {
                do { try await connect(ticket: ticket); attempt = 0 }
                catch { connected = false }
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
        if joined { rooms.insert(id) } else { rooms.remove(id) }
        guard connected else { return }
        Task { try? await send(joined ? "join" : "leave", ["conversation_id": .id(id)]) }
    }
    private func send(_ type: String, _ payload: [String: JSON] = [:]) async throws {
        guard let connection else { throw URLError(.notConnectedToInternet) }
        let json = JSON.object(["type": .text(type), "payload": .object(payload)])
        try await connection.send(.string(String(decoding: try json.encoded(), as: UTF8.self)))
    }
    private func connect(ticket: UUID) async throws {
        guard let token = api.token else { return }
        var c = URLComponents(url: api.socketURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "access_token", value: token)]
        guard let url = c.url else { throw URLError(.badURL) }
        let socket = URLSession.shared.webSocketTask(with: url); connection = socket; socket.resume()
        lastFrame = Date()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        try await send("auth", ["token": .text(token)])
        let heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(20))
                    guard let self, self.runID == ticket else { return }
                    guard Date().timeIntervalSince(self.lastFrame) < 70 else {
                        socket.cancel(with: .goingAway, reason: nil); return
                    }
                    try await self.send("ping")
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
                try await send("sync", ["last_received_seq": .id(UserDefaults.standard.integer(forKey: sequenceKey)), "limit": .id(200)])
                for id in rooms { try await send("join", ["conversation_id": .id(id)]) }
            case "message": try await receive(frame, live: true)
            case "sync_result":
                for item in payload["list"].or(payload["messages"]).array { try await receive(item) }
                let current = UserDefaults.standard.integer(forKey: sequenceKey)
                let maximum = payload["current_max_seq"].int
                if payload["has_more"].bool {
                    try await send("sync", ["last_received_seq": .id(current), "limit": .id(200)])
                } else if maximum > current { UserDefaults.standard.set(maximum, forKey: sequenceKey) }
                revision += 1
            default: break
            }
        }
    }
    private func receive(_ frame: JSON, live: Bool = false) async throws {
        let seq = frame["seq"].int, previous = UserDefaults.standard.integer(forKey: sequenceKey)
        if live && (seq == 0 || seq > previous) { onLiveEvent?(frame["payload"].or(frame), seq) }
        if seq == 0 || seq > previous { revision += 1 }
        if seq > previous { UserDefaults.standard.set(seq, forKey: sequenceKey) }
        if seq > 0 { try await send("ack_receive", ["seq": .id(seq)]) }
    }
}
