//  墨阅 InkReader · InkReader/Views/Library/LanShareView.swift
//  功能：局域网共享界面 —— 主机端显示本机地址可复制、勾选要共享的书；客户端自动发现或手填 IP + 端口 + 密码后下载。
//  要点：下载到的书直接写文件 + 封面并加入书架。

import SwiftUI
import UIKit

/// 局域网加密共享：一边当主机把书共享出去，一边当客户端去别人那儿取书
struct LanShareView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case host
        case client
        var id: String { rawValue }
        var title: String {
            switch self {
            case .host: return "共享我的书"
            case .client: return "去别人那儿取"
            }
        }
    }

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .host
    @StateObject private var host = LanShareHost()
    @StateObject private var browser = LanServiceBrowser()
    @StateObject private var client = LanShareClient()

    @State private var deviceName = UIDevice.current.name
    @State private var password = ""
    @State private var selected: Set<UUID> = []

    @State private var manualHost = ""
    @State private var manualPort = "8899"
    @State private var clientPassword = ""
    @State private var downloading: Set<UUID> = []
    @State private var alertMessage: String?
    @State private var toast: String?

    init(preselected: Set<UUID> = []) {
        self._selected = State(initialValue: preselected)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("角色", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .host {
                    hostSection
                } else {
                    clientSection
                }

                Section {
                    Text("书是在本机用密码加密之后才发出去的，局域网上只跑密文；"
                         + "主机端只有勾选过的书会响应，没勾选的就算被点名也拿不到。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("局域网共享")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        host.stop()
                        browser.stop()
                        client.disconnect()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                host.stop()
                browser.stop()
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好") { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.opacity)
                }
            }
            .onChange(of: toast) { _, _ in
                guard toast != nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { toast = nil }
            }
        }
    }

    // MARK: - 主机端

    private var hostSection: some View {
        Group {
            Section("共享设置") {
                TextField("本机名称", text: $deviceName)
                SecureField("共享密码（对方要用同一个）", text: $password)
                Button(host.isRunning ? "停止共享" : "开始共享") {
                    host.isRunning ? host.stop() : startHost()
                }
                .disabled(!host.isRunning && password.trimmed.isEmpty)

                HStack {
                    Text("状态")
                    Spacer()
                    Text(host.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if host.isRunning {
                    HStack {
                        Text("已连接")
                        Spacer()
                        Text("\(host.connectionCount) 台")
                            .foregroundStyle(.secondary)
                    }
                    if !host.lastEvent.isEmpty {
                        Text(host.lastEvent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // 本机地址直接列出来，方便抄给对方手填
            if host.isRunning {
                Section("本机地址") {
                    if host.shareAddresses.isEmpty {
                        Text("没取到局域网地址，检查是不是连着 Wi-Fi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(host.shareAddresses, id: \.self) { address in
                            HStack {
                                Text(address)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = address
                                    toast = "已复制 \(address)"
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            Section("共享哪些书（\(selected.count)）") {
                if library.books.isEmpty {
                    Text("书架还是空的")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(library.sortedBooks(keyword: "")) { book in
                        Button {
                            toggle(book.id)
                        } label: {
                            HStack {
                                Image(systemName: book.format.symbolName)
                                    .foregroundStyle(.secondary)
                                Text(book.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selected.contains(book.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(book.id)
                                                     ? Color.accentColor : Color.secondary)
                            }
                        }
                    }
                    HStack {
                        Button("全选") { selected = Set(library.books.map { $0.id }) }
                        Button("全不选") { selected.removeAll() }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - 客户端

    private var clientSection: some View {
        Group {
            Section("自动发现") {
                Button {
                    browser.start()
                } label: {
                    Label("查找局域网里的墨阅", systemImage: "magnifyingglass")
                }
                if !browser.status.isEmpty {
                    Text(browser.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(browser.found) { item in
                    Button {
                        manualHost = item.host
                        manualPort = String(item.port)
                        connect()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text(item.address)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle")
                        }
                    }
                }
            }

            Section("手填地址") {
                TextField("IP 地址", text: $manualHost)
                    .keyboardType(.decimalPad)
                TextField("端口", text: $manualPort)
                    .keyboardType(.numberPad)
                SecureField("对方的共享密码", text: $clientPassword)
                Button(client.isConnected ? "断开" : "连接") {
                    client.isConnected ? client.disconnect() : connect()
                }
                .disabled(manualHost.trimmed.isEmpty || clientPassword.trimmed.isEmpty)
                if !client.status.isEmpty {
                    Text(client.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if client.isConnected {
                Section("对方的书（\(client.books.count)）") {
                    if client.books.isEmpty {
                        Text("对方还没共享任何书")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(client.books) { info in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.title)
                                    Text("\(Self.formatTitle(info.format)) · "
                                         + "\(ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if downloading.contains(info.id) {
                                    ProgressView()
                                } else if library.books.contains(where: { $0.title == info.title }) {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("下载") { download(info) }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 动作

    private func startHost() {
        host.deviceName = deviceName.trimmed.isEmpty ? "墨阅 iPad" : deviceName
        host.password = password
        host.allowedBookIds = selected
        host.library = library
        host.start()
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        host.allowedBookIds = selected
    }

    private func connect() {
        guard let port = Int(manualPort.trimmingCharacters(in: .whitespaces)) else {
            alertMessage = "端口得是数字"
            return
        }
        client.connect(host: manualHost.trimmed, port: port, password: clientPassword) { result in
            switch result {
            case .success:
                client.fetchBooks { _ in }
            case .failure(let error):
                alertMessage = error.localizedDescription
            }
        }
    }

    private func download(_ info: ShareBookInfo) {
        downloading.insert(info.id)
        client.download(id: info.id) { [self] result in
            downloading.remove(info.id)
            switch result {
            case .success(let payload):
                importPayload(payload)
                toast = "已接收「\(payload.info.title)」"
            case .failure(let error):
                alertMessage = error.localizedDescription
            }
        }
    }

    /// 把收到的书落成本地的一本：写文件、写封面、进书架
    private func importPayload(_ payload: ShareBookPayload) {
        guard let data = Data(base64Encoded: payload.fileBase64) else {
            alertMessage = "收到的数据解不开"
            return
        }
        let format = BookFormat(rawValue: payload.info.format) ?? .txt
        let fileName = "\(UUID().uuidString).\(Self.fileExtension(for: format))"
        let target = Storage.booksDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: target)
        } catch {
            alertMessage = "写入失败：\(error.localizedDescription)"
            return
        }

        var book = Book(
            id: UUID(),
            title: payload.info.title,
            author: payload.info.author,
            format: format,
            fileName: fileName,
            fileSize: Int64(data.count)
        )
        book.totalPages = payload.info.totalPages
        book.locator = payload.info.locator
        book.progress = payload.info.progress
        book.lastReadAt = Date()

        if let base64 = payload.coverBase64,
           let coverData = Data(base64Encoded: base64),
           let image = UIImage(data: coverData),
           let png = image.pngData() {
            let name = "\(book.id.uuidString).png"
            try? png.write(to: Storage.coversDirectory.appendingPathComponent(name))
            book.coverFileName = name
        }

        library.add(book)
    }

    private static func fileExtension(for format: BookFormat) -> String {
        switch format {
        case .txt, .epub: return "txt"     // EPUB 导入时就转成了纯文本
        case .pdf: return "pdf"
        case .comic: return "cbz"
        }
    }

    private static func formatTitle(_ raw: String) -> String {
        (BookFormat(rawValue: raw) ?? .txt).displayName
    }
}
