//  墨阅 InkReader · InkReader/Services/LanShare.swift
//  功能：局域网共享 —— 主机端 NWListener + Bonjour 发布，客户端 NetServiceBrowser 发现 + NWConnection 收发。
//  要点：帧格式是 4 字节大端长度 + 密文；Info.plist 必须有 NSLocalNetworkUsageDescription 和 NSBonjourServices。

import Darwin
import Foundation
import Network
import UIKit

// MARK: - 地址

enum LanAddress {
    /// 本机在局域网里的 IPv4 地址（给主机端显示「本机地址」用）
    static func localIPv4Addresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let interface = ptr.pointee
            let flags = Int32(interface.ifa_flags)
            if let addr = interface.ifa_addr,
               (flags & IFF_UP) != 0,
               (flags & IFF_LOOPBACK) == 0,
               addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let code = getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if code == 0 {
                    let text = String(cString: hostname)
                    if !text.isEmpty, !result.contains(text) { result.append(text) }
                }
            }
            cursor = interface.ifa_next
        }
        return result
    }

    /// 从 Bonjour 解析结果里挑出 IPv4 的 host / port
    static func parseAddresses(_ service: NetService) -> [(host: String, port: Int)] {
        var result: [(host: String, port: Int)] = []
        for data in service.addresses ?? [] {
            guard data.count >= MemoryLayout<sockaddr_in>.size else { continue }
            let family = data.withUnsafeBytes { $0.load(as: sockaddr.self) }.sa_family
            guard family == UInt8(AF_INET) else { continue }
            var sin = data.withUnsafeBytes { $0.load(as: sockaddr_in.self) }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let code = withUnsafeMutablePointer(to: &sin) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    getnameinfo(
                        sa,
                        socklen_t(MemoryLayout<sockaddr_in>.size),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                }
            }
            guard code == 0 else { continue }
            let host = String(cString: hostname)
            let port = Int(UInt16(bigEndian: sin.sin_port))
            if !host.isEmpty, port > 0 { result.append((host, port)) }
        }
        return result
    }
}

// MARK: - 协议报文

/// 每条消息都用扁平结构而不是带关联值的枚举：
/// 合成的 Codable 对带关联值的枚举支持得不直观，扁平结构更容易对得上版本。
struct LanEnvelope: Codable {
    var kind: String
    var deviceName: String?
    var books: [ShareBookInfo]?
    var bookId: UUID?
    var payload: ShareBookPayload?
    var message: String?
}

enum LanKind {
    static let hello = "hello"
    static let list = "list"
    static let get = "get"
    static let error = "error"
}

struct ShareBookInfo: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var author: String
    /// BookFormat.rawValue
    var format: String
    var totalPages: Int
    var fileSize: Int64
    var hasCover: Bool
    var progress: Double
    var locator: String
}

struct ShareBookPayload: Codable, Equatable {
    var info: ShareBookInfo
    var fileBase64: String
    var coverBase64: String?
}

/// 4 字节大端长度 + 正文
enum LanFraming {
    static func encode(_ body: Data) -> Data {
        let len = UInt32(body.count)
        var out = Data()
        out.append(contentsOf: [
            UInt8((len >> 24) & 0xff),
            UInt8((len >> 16) & 0xff),
            UInt8((len >> 8) & 0xff),
            UInt8(len & 0xff)
        ])
        out.append(body)
        return out
    }
}

// MARK: - 连接

/// 一条 TCP 连接：负责收发「定长头 + 密文」
final class LanConnection {
    let raw: NWConnection
    private var buffer = Data()
    var onMessage: ((Data) -> Void)?
    var onClose: (() -> Void)?
    private var closed = false

    init(_ raw: NWConnection) {
        self.raw = raw
    }

    func start(queue: DispatchQueue) {
        raw.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.finish()
            default:
                break
            }
        }
        raw.start(queue: queue)
        pump()
    }

    func send(_ body: Data) {
        raw.send(content: LanFraming.encode(body), completion: .contentProcessed { _ in })
    }

    func cancel() {
        finish()
        raw.cancel()
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        onClose?()
    }

    private func pump() {
        raw.receive(minimumIncompleteLength: 4, maximumLength: 512 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drain()
            }
            if error != nil || isComplete {
                self.finish()
                return
            }
            if !self.closed { self.pump() }
        }
    }

    private func drain() {
        while buffer.count >= 4 {
            let start = buffer.startIndex
            let len = Int(buffer[start]) << 24
                | Int(buffer[start + 1]) << 16
                | Int(buffer[start + 2]) << 8
                | Int(buffer[start + 3])
            guard buffer.count >= 4 + len else { break }
            let body = buffer.subdata(in: (start + 4)..<(start + 4 + len))
            buffer.removeSubrange(start..<(start + 4 + len))
            onMessage?(body)
        }
    }
}

// MARK: - 主机端

/// 把选中的几本书在局域网里共享出去
///
/// 只有 allowedBookIds 里的书会被发出去，不在清单里的书就算伪造请求也拿不到。
final class LanShareHost: ObservableObject {
    static let serviceType = "_inkreader._tcp"
    /// 端口池：固定几个，方便对方手填地址（listener 没能报端口也能自己记）
    private static let candidatePorts = [8899, 8900, 8901, 8902]

    @Published var isRunning = false
    @Published var status = "未开启"
    @Published var port: Int = 0
    @Published var addresses: [String] = []
    @Published var connectionCount = 0
    @Published var lastEvent = ""

    var deviceName: String = UIDevice.current.name
    var password: String = ""
    var allowedBookIds: Set<UUID> = []
    var library: LibraryStore?

    private var listener: NWListener?
    private var sessions: [LanConnection] = []
    private let queue = DispatchQueue(label: "inkreader.lanshare.host", qos: .userInitiated)
    private var portIndex = 0

    /// 共享地址，直接显示给用户抄
    var shareAddresses: [String] {
        guard port > 0 else { return [] }
        return addresses.map { "\($0):\(port)" }
    }

    func start() {
        guard !isRunning else { return }
        guard !password.trimmed.isEmpty else {
            status = "先设一个共享密码"
            return
        }
        guard !allowedBookIds.isEmpty else {
            status = "先在书架上勾选要共享的书"
            return
        }
        addresses = LanAddress.localIPv4Addresses()
        portIndex = 0
        tryNextPort()
    }

    private func tryNextPort() {
        guard portIndex < Self.candidatePorts.count else {
            status = "端口都被占用了，换个网络再试"
            return
        }
        let portNumber = Self.candidatePorts[portIndex]
        portIndex += 1

        let parameters = NWParameters.tcp
        var listener: NWListener
        do {
            guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(portNumber)) else {
                tryNextPort()
                return
            }
            listener = try NWListener(using: parameters, on: endpointPort)
        } catch {
            tryNextPort()
            return
        }

        listener.service = NWListener.Service(name: deviceName, type: Self.serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.port = portNumber
                    self.addresses = LanAddress.localIPv4Addresses()
                    self.isRunning = true
                    self.status = "已开启，等对方来连"
                case .failed:
                    self.isRunning = false
                    self.tryNextPort()
                case .cancelled:
                    self.isRunning = false
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for session in sessions { session.cancel() }
        sessions.removeAll()
        isRunning = false
        port = 0
        connectionCount = 0
        status = "已停止"
    }

    private func accept(_ connection: NWConnection) {
        let session = LanConnection(connection)
        session.onMessage = { [weak self, weak session] body in
            guard let self, let session else { return }
            self.handle(body, reply: { session.send($0) })
        }
        session.onClose = { [weak self, weak session] in
            guard let self else { return }
            DispatchQueue.main.async {
                if let session { self.sessions.removeAll { $0 === session } }
                self.connectionCount = self.sessions.count
            }
        }
        sessions.append(session)
        session.start(queue: queue)
        DispatchQueue.main.async { self.connectionCount = self.sessions.count }
    }

    // MARK: 处理请求

    private func handle(_ body: Data, reply: (Data) -> Void) {
        guard let envelope = try? ShareCrypto.open(LanEnvelope.self, from: body, password: password) else {
            respondError(ShareError.passwordMismatch, reply: reply)
            return
        }

        switch envelope.kind {
        case LanKind.hello:
            respond(LanEnvelope(kind: LanKind.hello, deviceName: deviceName), reply: reply)
        case LanKind.list:
            let list = sharedBooks()
            respond(LanEnvelope(kind: LanKind.list, deviceName: deviceName, books: list), reply: reply)
            DispatchQueue.main.async {
                self.lastEvent = "对方取走了书单（\(list.count) 本）"
            }
        case LanKind.get:
            guard let id = envelope.bookId, allowedBookIds.contains(id) else {
                respondError(ShareError.notShared, reply: reply)
                return
            }
            guard let payload = makePayload(bookId: id) else {
                respondError(ShareError.notShared, reply: reply)
                return
            }
            respond(LanEnvelope(kind: LanKind.get, payload: payload), reply: reply)
            DispatchQueue.main.async {
                self.lastEvent = "已发送「\(payload.info.title)」"
            }
        default:
            respondError(ShareError.passwordMismatch, reply: reply)
        }
    }

    private func sharedBooks() -> [ShareBookInfo] {
        guard let library else { return [] }
        return library.books
            .filter { allowedBookIds.contains($0.id) }
            .map { Self.info(of: $0) }
    }

    private func makePayload(bookId: UUID) -> ShareBookPayload? {
        guard let book = library?.book(withId: bookId) else { return nil }
        guard let data = try? Data(contentsOf: book.fileURL) else { return nil }
        // base64 会把体积撑大 1/3，太大的书直接放弃，免得两头都卡死
        guard data.count < 200 * 1024 * 1024 else { return nil }
        var cover: String?
        if let url = book.coverURL, let coverData = try? Data(contentsOf: url) {
            cover = coverData.base64EncodedString()
        }
        return ShareBookPayload(
            info: Self.info(of: book),
            fileBase64: data.base64EncodedString(),
            coverBase64: cover
        )
    }

    private static func info(of book: Book) -> ShareBookInfo {
        ShareBookInfo(
            id: book.id,
            title: book.title,
            author: book.author,
            format: book.format.rawValue,
            totalPages: book.totalPages,
            fileSize: book.fileSize,
            hasCover: book.coverFileName != nil,
            progress: book.progress,
            locator: book.locator
        )
    }

    private func respond(_ envelope: LanEnvelope, reply: (Data) -> Void) {
        guard let body = try? ShareCrypto.seal(envelope, password: password) else { return }
        reply(body)
    }

    private func respondError(_ error: Error, reply: (Data) -> Void) {
        let envelope = LanEnvelope(
            kind: LanKind.error,
            message: error.localizedDescription
        )
        respond(envelope, reply: reply)
    }
}

// MARK: - 发现

/// 用 Bonjour 自动发现同一局域网里的墨阅
final class LanServiceBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    struct Found: Identifiable {
        var name: String
        var host: String
        var port: Int
        var id: String { "\(name)|\(host):\(port)" }
        var address: String { "\(host):\(port)" }
    }

    @Published var found: [Found] = []
    @Published var status = ""

    private let browser = NetServiceBrowser()
    private var pending: [NetService] = []

    func start() {
        stop()
        status = "正在查找…"
        browser.delegate = self
        browser.searchForServices(ofType: LanShareHost.serviceType, inDomain: "local.")
    }

    func stop() {
        browser.stop()
        for service in pending { service.stop() }
        pending.removeAll()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
        service.delegate = self
        pending.append(service)
        service.resolve(withTimeout: 5)
        if !moreComing {
            DispatchQueue.main.async {
                if self.found.isEmpty { self.status = "正在解析地址…" }
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didNotSearch errorDict: [String: NSNumber]) {
        DispatchQueue.main.async {
            self.status = "查找失败，检查「本地网络」权限是否打开"
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let address = LanAddress.parseAddresses(sender).first else { return }
        let item = Found(name: sender.name, host: address.host, port: address.port)
        DispatchQueue.main.async {
            if !self.found.contains(where: { $0.id == item.id }) {
                self.found.append(item)
            }
            self.status = "找到 \(self.found.count) 台设备"
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        DispatchQueue.main.async {
            if self.found.isEmpty { self.status = "解析地址失败，也可以手填地址" }
        }
    }
}

// MARK: - 客户端

/// 连到另一台墨阅，取书单、下载书
final class LanShareClient: ObservableObject {
    @Published var books: [ShareBookInfo] = []
    @Published var remoteName = ""
    @Published var status = ""

    private var connection: LanConnection?
    private var password = ""
    private let queue = DispatchQueue(label: "inkreader.lanshare.client", qos: .userInitiated)
    private var waiting: ((LanEnvelope) -> Void)?

    var isConnected: Bool { connection != nil }

    func disconnect() {
        connection?.cancel()
        connection = nil
        waiting = nil
        books = []
        remoteName = ""
        status = "已断开"
    }

    func connect(host: String,
                 port: Int,
                 password: String,
                 completion: @escaping (Result<String, Error>) -> Void) {
        disconnect()
        self.password = password
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            completion(.failure(ShareError.badAddress))
            return
        }
        let hostEndpoint = NWEndpoint.Host.name(host, nil)
        let connection = NWConnection(
            host: hostEndpoint,
            port: endpointPort,
            using: NWParameters.tcp
        )
        let session = LanConnection(connection)
        session.onClose = { [weak self] in
            DispatchQueue.main.async {
                self?.status = self?.status == "已断开" ? "已断开" : "连接断开了"
            }
        }
        session.onMessage = { [weak self] body in
            self?.receive(body)
        }
        self.connection = session
        session.start(queue: queue)

        send(LanEnvelope(kind: LanKind.hello)) { [weak self] envelope in
            guard let self else { return }
            DispatchQueue.main.async {
                if envelope.kind == LanKind.error {
                    self.disconnect()
                    completion(.failure(ShareError.passwordMismatch))
                    return
                }
                self.remoteName = envelope.deviceName ?? "对方设备"
                self.status = "已连上「\(self.remoteName)」"
                completion(.success(self.remoteName))
            }
        }
    }

    func fetchBooks(completion: @escaping (Result<[ShareBookInfo], Error>) -> Void) {
        send(LanEnvelope(kind: LanKind.list)) { [weak self] envelope in
            guard let self else { return }
            DispatchQueue.main.async {
                if envelope.kind == LanKind.error {
                    completion(.failure(ShareError.notShared))
                    return
                }
                self.books = envelope.books ?? []
                completion(.success(self.books))
            }
        }
    }

    func download(id: UUID, completion: @escaping (Result<ShareBookPayload, Error>) -> Void) {
        send(LanEnvelope(kind: LanKind.get, bookId: id)) { envelope in
            DispatchQueue.main.async {
                if envelope.kind == LanKind.error {
                    completion(.failure(ShareError.notShared))
                    return
                }
                guard let payload = envelope.payload else {
                    completion(.failure(ShareError.notShared))
                    return
                }
                completion(.success(payload))
            }
        }
    }

    // MARK: 内部

    private func send(_ envelope: LanEnvelope, handler: @escaping (LanEnvelope) -> Void) {
        guard let connection else {
            DispatchQueue.main.async { self.status = "还没连上对方" }
            return
        }
        guard let body = try? ShareCrypto.seal(envelope, password: password) else { return }
        waiting = handler
        connection.send(body)
    }

    private func receive(_ body: Data) {
        guard let handler = waiting else { return }
        waiting = nil
        guard let envelope = try? ShareCrypto.open(LanEnvelope.self, from: body, password: password) else {
            DispatchQueue.main.async { self.status = "解不开对方的消息，密码是不是不一样？" }
            return
        }
        handler(envelope)
    }
}
