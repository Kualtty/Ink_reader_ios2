# 墨阅 InkReader · 架构说明

> 面向 iPadOS 17 的原生阅读器。这份文档说明代码怎么分层、每个文件干什么、数据存在哪，
> 以及改代码时必须遵守的几条硬规矩。每个 Swift 文件的开头也有两行注释（功能 + 要点），改文件前先看那两行。

---

## 1. 技术栈

- **SwiftUI + UIKit 混编**：文本用 `UITextView`、PDF 用 PDFKit、手写用 PencilKit，都用 `UIViewRepresentable` 包一层
- **部署目标 iPadOS 17.0**：**不要引入 iOS 18+ 的 API**，否则老设备装不上
- **唯一外部依赖**：`ZIPFoundation`（SPM），用于 CBZ / ZIP / EPUB 解压与整库备份
- **无后端**：局域网共享自己用 Network.framework 实现（Bonjour 发现 + TCP 收发 + AES-GCM 加密）

---

## 2. 分层结构

```
InkReaderApp                 创建全局 Store，以 environmentObject 注入整棵视图树
   │
   ├── Views                 只负责界面、手势与弹层，不含业务逻辑
   │     ├── Library         书架 / 收藏夹 / 备份 / 局域网共享 / 漫画页面管理
   │     ├── Reader          阅读器容器 + 各格式的具体阅读器
   │     └── Overlays        目录与搜索、笔记、设置、查词、涂鸦层、原文修订
   │
   ├── ReaderViewModel       阅读器中枢：装载书籍、翻页、标注、播读、修订
   │
   ├── Services              业务逻辑与持久化（不碰界面）
   │
   └── Models                纯数据结构
```

**数据流是单向的**：`View → ViewModel → Service → 磁盘`。
View 不直接读写文件，Service 不直接引用 View。全局 Store 只在 `InkReaderApp` 里创建一次，
其它页面一律用 `@EnvironmentObject` 取，不要自己 `new`。

---

## 3. 目录与文件职责

```
InkReader/
├── InkReaderApp.swift                 App 入口：创建并注入全局 Store；AppRootView 装配首屏
│
├── Models/                            纯数据结构，不含逻辑
│   ├── Book.swift                     书籍（id / 标题 / 格式 / 封面 / 进度 / 置顶时间）+ BookFormat + Chapter
│   ├── Bookmark.swift                 书签 Bookmark、笔记 Note、高亮区间 HighlightRange
│   ├── Collection.swift               收藏夹 BookCollection（只存 bookId，不存书籍对象）
│   └── ReadingSettings.swift          主题、字号、行距、对齐、翻页方向、漫画模式、自动翻页速度
│
├── Services/                          业务逻辑与持久化
│   ├── AnnotationStore.swift          书签 / 笔记 / 高亮 / 涂鸦的增删改查；页序变化后搬迁标注
│   ├── BackupService.swift            整库备份、按选择备份、导入（合并或覆盖）
│   ├── BookImporter.swift             导入分发：txt / pdf / epub / cbz / 图片 → 写文件、抽封面、登记书架
│   ├── ChapterParser.swift            用正则从 TXT 正文抽章节标题与位置
│   ├── CollectionStore.swift          收藏夹的增删改、重命名、改色、批量移入移出
│   ├── ComicExtractor.swift           cbz / zip / 散图解压成有序页文件
│   ├── ComicPageStore.swift           漫画页序：排序、删页、从某页拆开、合入另一本
│   ├── EPUBParser.swift               container.xml → OPF → spine，拼出纯文本与章节
│   ├── ExportService.swift            导出笔记 Markdown、导出原文件、iPad 分享面板
│   ├── LanShare.swift                 局域网共享：NWListener 主机端 / NetServiceBrowser 发现 / NWConnection 收发
│   ├── LibraryStore.swift             书籍增删改、排序（置顶优先）、重命名、置顶、清数据
│   ├── ShareCrypto.swift              PBKDF2-HMAC-SHA256 + AES-GCM（PBKDF2 是手写实现）
│   ├── SpeechService.swift            播读：分块朗读、暂停 / 继续 / 跳句、高亮当前句
│   ├── Storage.swift                  统一的目录路径与创建（Books / Caches / 涂鸦）
│   ├── TextEncodingDetector.swift     编码探测：UTF-8 / UTF-16 / GBK / GB18030 / Big5
│   ├── TextRevision.swift             原文修订：记录改动、平移标注、标记失效、撤销、重新定位
│   └── TxtPaginator.swift             TXT 分页：TextKit 多 NSTextContainer，后台队列 + NSLock
│
├── Utils/
│   ├── Color+Hex.swift                hex 字符串与 Color / UIColor 互转
│   └── VolumeKeyObserver.swift        音量键翻页（隐藏 MPVolumeView + KVO）
│
├── Views/
│   ├── Library/
│   │   ├── LibraryView.swift          书架主页：网格卡片、搜索、排序、多选批量、导入
│   │   ├── LibrarySidebarView.swift   侧栏：全部 / 收藏夹 / 按格式筛选
│   │   ├── CollectionsView.swift      收藏夹管理：重命名、改色、删除、批量移入
│   │   ├── BackupView.swift           备份与恢复界面
│   │   ├── ComicPagesView.swift       漫画页面管理：排序、删页、拆分、合并
│   │   └── LanShareView.swift         局域网共享界面：本机地址、选书、发现与下载
│   │
│   ├── Reader/
│   │   ├── ReaderContainerView.swift  阅读器容器：顶栏底栏、手势、sheet 路由、自动翻页计时
│   │   ├── ReaderViewModel.swift      阅读器业务中枢（装载 / 翻页 / 标注 / 播读 / 修订）
│   │   ├── TxtPagedReader.swift       TXT 横向翻页阅读器
│   │   ├── TxtScrollReader.swift      TXT 连续滚动阅读器
│   │   ├── PageTextView.swift         单页文本视图 + 划词菜单
│   │   ├── PdfReaderView.swift        PDFKit 阅读器
│   │   ├── PdfSearchView.swift        PDF 全文搜索
│   │   └── ComicReaderView.swift      漫画阅读器：缓存、缩放、四种翻页方向
│   │
│   └── Overlays/
│       ├── ChapterListView.swift      章节目录 + 全文搜索
│       ├── NoteComposer.swift         写笔记 / 加书签 / 笔记列表
│       ├── SettingsPanel.swift        阅读设置面板
│       ├── LookupView.swift           系统词典、Safari 小窗、搜索引擎
│       ├── AnnotationCanvasView.swift PencilKit 涂鸦层
│       └── TextRevisionView.swift     编辑原文、修订记录、撤销、失效标注重定位
│
├── Info.plist                         含 NSLocalNetworkUsageDescription 与 NSBonjourServices
└── Assets.xcassets                    图标与主题色
```

工程外还有：

| 路径 | 作用 |
| --- | --- |
| `InkReader.xcodeproj/project.pbxproj` | 由 `tools/gen_xcodeproj.py` 生成，**不要手改** |
| `InkReader.xcodeproj/xcshareddata/xcschemes/` | shared scheme，CI 编译依赖它（放 `xcuserdata` 会被 git 忽略） |
| `.github/workflows/build-unsigned-ipa.yml` | GitHub Actions 编译未签名 ipa |
| `tools/check_sources.py` | 自检：文件是否漏登记、括号是否配平 |
| `tools/gen_xcodeproj.py` | 生成 pbxproj 与 scheme；**新增 Swift 文件后必须重跑** |
| `tools/pack.py` | 打包成 `dist/InkReader-iPad`（`--zip` 顺带出压缩包） |

---

## 4. 关键流程

**导入**：`LibraryView` 选文件 → `BookImporter` 按扩展名分发 → 写进 `Documents/Books/` → 抽封面 → `LibraryStore.add()`

**阅读**：`ReaderContainerView` → `ReaderViewModel.load()` → 按格式选 `TxtPagedReader` / `TxtScrollReader` / `PdfReaderView` / `ComicReaderView`

**标注**：划词 → `PageTextView` 菜单 → `AnnotationStore` 落盘；涂鸦 → `AnnotationCanvasView` 按页或屏锚点存 `.drawing` 文件

**修订**（仅 TXT / EPUB）：划词 → 编辑原文 → `TextRevisionEngine` 改字符串并平移标注 → 重叠的标注进失效列表，可重新定位或丢弃

**备份**：`BackupService` 打包书籍文件 + 封面 + 标注 + 设置成 zip；导入时可选合并或覆盖

**共享**：主机端 `LanShareHost` 起 `NWListener` 并发布 Bonjour → 客户端 `NetServiceBrowser` 发现 → 输入密码 → `NWConnection` 收密文 → `ShareCrypto` 解密 → 写文件入书架

---

## 5. 数据存在哪

| 内容 | 位置 |
| --- | --- |
| 书籍原文件与封面 | `Documents/Books/` |
| 书架 | `Documents/library.json`（由 `LibraryStore` 管） |
| 收藏夹 | `Documents/collections.json` |
| 书签 / 笔记 / 高亮 | `Documents/annotations.json` |
| 涂鸦笔迹 | 每本书一个 `.drawing` 文件 |
| 修订记录与失效标注 | `Documents/revisions.json` |
| 漫画自定义页序 | `Documents/comicpages.json` |
| 压缩包的解压页 | `Caches/`（**可能被系统清空，所以页序存包内相对路径**） |

---

## 6. 改代码前必须知道的几条

1. **新增 Swift 文件后要跑 `python3 tools/gen_xcodeproj.py`**，否则不会进工程，CI 上会报找不到符号。
2. **容错解码只能写在 `extension` 里**。写进 `struct` 体内会让成员构造器消失，`BookImporter` 直接编译不过。
3. **Swift 不支持 tuple key path**：`ForEach(Array(x.enumerated()), id: \.offset)` 编译不过，用 `ForEach(0..<n, id: \.self)`。
4. **ViewBuilder 里别写 `let`**，改用计算属性。
5. **涂鸦层的 `show` 与 `active` 是两个状态**，别合并——合并后完成后笔迹会消失。
6. **`remapPages` 收到空映射要直接 return**，否则会把整本标注清空。
7. **`@Published private(set)` 外部不能赋值**，需要整体重置时另开一个 `reset()`。
8. **iPad 的分享面板必须设 `sourceView` 且清空箭头方向**，否则崩溃。
9. **不要引入 iOS 18+ API**，部署目标是 iPadOS 17.0。
10. **不要 `shutil.rmtree` 打包目录**（会触发批量删除拦截），直接覆盖写。

---

## 7. 已知限制

- EPUB 导入后转成纯文本，保留章节但丢掉原有排版与图片
- CBR（RAR 压缩的漫画）不支持
- 滚动模式下涂鸦按屏序号锚定，改字号后位置会偏移
- 整库备份暂不含修订记录与漫画自定义页序
- 局域网共享单本书超过 200 MB 会拒绝
