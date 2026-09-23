//  墨阅 InkReader · InkReader/Views/Overlays/LookupView.swift
//  功能：查词与网页查询 —— 系统词典（UIReferenceLibraryViewController）、Safari 小窗、搜索引擎跳转。
//  要点：SearchEngines 里可加更多引擎。

import SafariServices
import SwiftUI
import UIKit

// MARK: - 系统词典（离线，iOS 自带）

/// 直接用系统的 `UIReferenceLibraryViewController`。
/// `init(term:)` 是非可失败的：查不到时它会自己显示一条本地化的「未找到」提示，
/// 所以不用在外面判空，但可以用 `dictionaryHasDefinition` 提前给个提示。
struct DictionaryViewController: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {
        // 词条不变就不重建
    }
}

// MARK: - App 内网页查询

/// Safari 视图：不跳出 App，也不用自己实现浏览器
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {
        // 换词条时整个 sheet 会重建，这里不用处理
    }
}

// MARK: - 词条（给 .sheet(item:) 用）

struct LookupTerm: Identifiable {
    let id = UUID()
    var text: String
}

// MARK: - 查词面板

struct LookupSheet: View {
    @State var term: String
    @Environment(\.dismiss) private var dismiss

    @State private var showDictionary = false
    @State private var webURL: URL?
    @State private var hasDefinition: Bool?

    private static let engines: [(name: String, icon: String, make: (String) -> URL?)] = [
        ("必应", "magnifyingglass", { SearchEngines.bing($0) }),
        ("百度", "globe.asia.australia", { SearchEngines.baidu($0) }),
        ("有道词典", "character.book.closed", { SearchEngines.youdao($0) }),
        ("维基百科", "book.closed", { SearchEngines.wikipedia($0) })
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("要查的词", text: $term)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                        Button {
                            showDictionary = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .disabled(term.trimmed.isEmpty)
                    }
                } header: {
                    Text("词条")
                } footer: {
                    if hasDefinition == false {
                        Text("系统词典里没有这个词的释义，可以试试下面的网页查询。")
                    }
                }

                Section {
                    Button {
                        showDictionary = true
                    } label: {
                        Label("查系统词典", systemImage: "book")
                    }
                    .disabled(term.trimmed.isEmpty)
                } header: {
                    Text("离线")
                } footer: {
                    Text("iPad 自带的词典，不联网。中文释义需要在「设置 → 通用 → 字典」里下载过对应词典。")
                }

                Section {
                    ForEach(Self.engines, id: \.name) { engine in
                        Button {
                            webURL = engine.make(term)
                        } label: {
                            HStack {
                                Image(systemName: engine.icon)
                                    .frame(width: 22)
                                Text(engine.name)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(term.trimmed.isEmpty)
                    }
                } header: {
                    Text("网页查询")
                } footer: {
                    Text("在 App 内打开，不会跳到 Safari。")
                }
            }
            .navigationTitle("查词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showDictionary) {
                DictionaryViewController(term: term.trimmed)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(
                get: { webURL != nil },
                set: { if !$0 { webURL = nil } }
            )) {
                if let url = webURL {
                    SafariView(url: url).ignoresSafeArea()
                }
            }
            .onAppear {
                let word = term.trimmed
                hasDefinition = word.isEmpty
                    ? nil
                    : UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: word)
            }
            .onChange(of: term) { _, newValue in
                let word = newValue.trimmed
                hasDefinition = word.isEmpty
                    ? nil
                    : UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: word)
            }
        }
    }
}

// MARK: - 搜索引擎

enum SearchEngines {
    private static func url(_ base: String, _ term: String) -> URL? {
        guard !term.trimmed.isEmpty,
              let encoded = term.trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: base + encoded)
    }

    static func bing(_ term: String) -> URL? {
        url("https://www.bing.com/search?q=", term)
    }

    static func baidu(_ term: String) -> URL? {
        url("https://www.baidu.com/s?wd=", term)
    }

    static func youdao(_ term: String) -> URL? {
        url("https://dict.youdao.com/result?word=", term)
    }

    static func wikipedia(_ term: String) -> URL? {
        url("https://zh.wikipedia.org/wiki/Special:Search?search=", term)
    }
}
