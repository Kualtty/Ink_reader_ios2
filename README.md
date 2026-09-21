# 墨阅 InkReader（iOS / SwiftUI）

一款支持 **TXT / PDF / EPUB / 漫画（CBZ·ZIP·图片）** 的本地阅读器，带手写涂鸦、笔记、书签、自动翻页、左右/上下切换、主题与字体调节。

- 语言：Swift 5 + SwiftUI
- 最低系统：**iOS / iPadOS 17.0**（iPhone / iPad 通用，在 iPadOS 18 上正常使用）
- 没有用到任何 iOS 18+ 的新 API，所以装不上系统的老设备也还能跑
- 依赖：仅一个 SPM 包 [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)（用于 CBZ/ZIP/EPUB 解压和整库备份，Xcode 会自动拉取）

---

## 〇、**没有 Mac 怎么办**（不想买 / 借不到）

iOS App 只能用 Xcode 编译，而 Xcode 只出 macOS 版 —— 所以需要一台 macOS 机器，
**但不一定要自己拥有一台**。按推荐顺序：

### 方案 1：GitHub Actions 免费编译（推荐先试）

仓库里已经放好了 `.github/workflows/build-unsigned-ipa.yml`：

1. 把这个仓库推到 GitHub（**公开仓库 macOS runner 才免费**）。
2. 打开仓库 → **Actions** → 选「编译未签名 ipa」→ **Run workflow**。
3. 等几分钟，Job 下面的 **Artifacts** 里会出现 `InkReader-unsigned-ipa`，下载解压得到 `InkReader-unsigned.ipa`。
4. 在 **Windows** 上用 [Sideloadly](https://sideloadly.io/)（免费）：
   插上 iPad → 选 ipa → 填你的 Apple ID → Start。它会用免费 Apple ID 重新签名并装到 iPad。

> 免费 Apple ID 签名 **7 天过期**，到期重跑一次第 4 步就行（不用重新编译）。

### 方案 2：租一台云 Mac

| 服务 | 大概价格 | 备注 |
| --- | --- | --- |
| MacinCloud | 约 $30/月，也有按小时 | 有 Xcode，远程桌面 |
| MacStadium | 按小时 / 按月 | 性能好 |
| AWS EC2 Mac | 按秒，**最少租 24 小时** | 按量付费，适合偶尔编一次 |

适合需要反复 Build、调 UI 的阶段。

### 方案 3：在 iPad 上直接开发（Swift Playgrounds）

iPad 装 **Swift Playgrounds 4+** 可以新建 App 项目并**直接在 iPad 上运行**，不需要电脑。
限制是：**不支持外部 SPM 包**。本项目目前依赖 ZIPFoundation（解压 CBZ/ZIP 和整库备份），
要搬到 Playgrounds 得先去掉这个依赖 —— 用系统自带的 **Compression** 框架自己写一份
inflate，就能脱离 SPM。改动量不大，需要的话可以让我来改。

### 方案 4：买台二手 Mac

M1 Mac mini 二手约 2000–3000 元，一次投入，之后随便调试，省去每次等 CI。

---

## 一、把 App 装到 iPad 上

> **目标设备是 iPad（iPadOS）。** Mac 在这里**只是编译机** —— iOS App 只能用 Xcode 编译，
> 而 Xcode 只出 macOS 版。除此之外整套交互、界面、存储都是按 iPad 的触屏 + Apple Pencil
> + 横竖屏设计的，Mac 上不会跑这个 App（也没有 Mac 版）。

步骤：

1. 把整个 `InkReader` 文件夹拷贝到 Mac（U 盘、AirDrop、Git 都行）。
2. 双击 `InkReader.xcodeproj` 用 Xcode 打开（Xcode 15+）。
3. 首次打开会提示 **Resolve Package**，点信任 / Trust 并等待 ZIPFoundation 拉取完成（需要联网）。
4. 左侧选中 `InkReader` 工程 → TARGETS → InkReader → **Signing & Capabilities**
   - 勾选 `Automatically manage signing`
   - Team 选择你的 Apple ID（免费账号即可）
   - 如果 Bundle Identifier 冲突，改成自己的，例如 `com.yourname.inkreader`
5. **用数据线把 iPad 接到 Mac**，顶部设备选择你的 iPad → `Cmd + R`。
   第一次需要在 iPad 的「设置 → 通用 → VPN 与设备管理」里信任一下开发者证书。

### 签名与有效期

| 账号类型 | 能做什么 | 限制 |
| --- | --- | --- |
| 免费 Apple ID | 真机调试（装到 iPad） | 签名 **7 天** 过期，到期重新连 Mac 点一次 Run 即可；最多 3 个 App ID |
| 付费开发者（¥688/年） | 真机 + TestFlight + 上架 | 签名有效期 1 年 |

> ⚠️ **没法在 Windows 上直接产出 ipa**，也不能绕过 Mac 无线装到 iPad。
> 没有 Mac 可以用云 Mac（MacinCloud、MacStadium）或 GitHub Actions 的 macOS runner 编译。

---

## 二、导入书籍

三种方式，任选：

1. **App 内导入**：书架左上角 `+` → 选择文件（支持多选，可以一次选几十张图片）。
2. **系统「文件」App**：iPad 上打开「文件」→ 找到 txt/pdf/epub/cbz → 分享 → 拷贝到「墨阅」。App 启动和书架菜单里都有「扫描导入」。
3. **拖放导入**：iPad 分屏/台前调度下，直接从「文件」App 把书**拖进书架**。
4. **电脑导入**：Mac Finder 连 iPad → 文件共享 → 墨阅 → 拖入文件，然后 App 内点「扫描」。

支持的扩展名：`txt / md / text`、`pdf`、`epub`、`cbz`、`zip`、以及 `jpg/png/webp/heic/gif/bmp` 图片。

---

## 三、功能一览

### 阅读
- **翻页方向**：左右翻页（分页）／上下滚动（连续阅读），随时一键切换
- **自动翻页**：1–60 秒 / 页可调，带常用档位（3s/5s/8s/12s/20s/30s），播放中可实时调速，到底自动停
- **音量键翻页**（设置里开关）、**点击屏幕**显示/隐藏工具栏、右下角常驻小圆点也能呼出菜单
- 进度条拖拽跳页、**点页码直接输数字跳转**、屏幕常亮
- **播读（TTS）**：从当前位置一路读下去，读的时候自动跟着翻页 / 滚屏
  - 悬浮播读条：暂停·继续、实时调速、显示当前正在读的那句、一键停止
  - 划选文字后菜单里有「朗读」，可以只读选中的一小段
  - 设置里能选语音（中英文）和语速，还有「试听一句」
  - PDF 按页朗读并同步页码；漫画没有文字，按钮自动置灰
- **查词**：划选文字 → 「查词」
  - 离线查 iPad 自带词典（`UIReferenceLibraryViewController`）
  - 也能在 App 内用必应 / 百度 / 有道 / 维基百科查（Safari 视图，不跳出 App）
  - 底栏「查词」按钮可以手动输入词条

### 排版与外观
- 字号 12–40、行距、字距、段距、页边距
- 字体：系统默认 + 苹方/宋体/楷体/圆体/Georgia/Times 等已装字体
- 粗体、左对齐 / 两端对齐 / 居中
- 背景主题：纯白、米黄、护眼绿、淡灰、夜间、纯黑，外加**自定义背景色 + 文字色**（取色器）
- 设置面板底部有实时预览

### 手写 / 涂鸦
- 基于 **PencilKit**，Apple Pencil 和手指都能画
- 钢笔 / 荧光笔 / 铅笔 / 橡皮，8 色画笔，粗细 1–18
- 撤销 / 重做 / 清空，自动按「当前页」保存
- 翻页后自动切到该页的涂鸦；已涂鸦的页会以静态图层显示

### 笔记与书签
- **划词 → 高亮 / 笔记**：长按选中正文，系统菜单里会出现「高亮」「笔记」
- 笔记支持 6 种标记色、编辑、删除；点列表项直接跳回原文位置
- 书签：一键添加当前页，带摘录文字，列表可跳转

### 目录与搜索
- TXT / EPUB 自动识别章节（第X章、Chapter N、数字编号、序章后记等）
- **文本书**：全文搜索，结果列表点击直达
- **PDF**：全文搜索（PDFKit 原生检索），结果带前后文摘要与页码，
  底部「上一个 / 下一个」显示 `2 / 7 · 第 41 页`，跳过去的同时把那一段高亮出来

### 收藏夹
- 新建 / 重命名 / **12 种配色** / 手动排序（上移·下移）
- 支持一层**嵌套子夹**（可把子夹移到顶层或别的夹下），最多 4 层
- 一本书可以同时属于多个收藏夹
- 「清空」只移出书、保留收藏夹；「删除」也只删收藏夹不动书
- 批量选择后可以整批「加入收藏夹」／「移出当前收藏夹」

### 备份与恢复
- 导出成 zip：书的文件 + 封面 + 阅读进度 + 笔记书签高亮 + 手写涂鸦 + 收藏夹 + 阅读设置
- 支持**只备份选中的几本书**（多选备份），不必每次全库
- 恢复分 **合并**（只补进备份里有、现在没有的；同 id 保留现有进度）
  和 **覆盖**（先清空现有数据再整体替换）两种模式

### 书架
- 网格封面（PDF 取首页缩略图、漫画取封面、TXT 生成文字封面）
- 搜索、排序（最近阅读/添加时间/书名/进度）、收藏、长按删除
- 阅读进度百分比，退出自动保存，重进自动回到上次位置

### iPad 专属（iPadOS 17 / 18 都跑得动）
- **左侧常驻侧栏**（`NavigationSplitView`）：书库 / 分类 / 收藏夹一栏全看到，带数量统计
- 从「文件」App **直接把书拖进书架**导入（拖放高亮提示）
- 横屏自动加宽网格，不再是把 iPhone 界面放大
- 接妙控键盘或外接键盘：
  - `⌘O` 导入
  - `← → ↑ ↓` / `PageUp PageDown` 阅读时翻页
- 批量操作条：全选 / 反选 / 全不选 / 批量收藏 / 批量加入收藏夹 / 批量删除

---

## 四、目录结构

```
InkReader/
├── InkReaderApp.swift          入口
├── Models/                     Book / Chapter / Bookmark / Note / ReadingSettings / Collection
├── Services/
│   ├── Storage.swift           目录与文件路径
│   ├── LibraryStore.swift      书架 + 全局设置持久化
│   ├── SpeechService.swift     播读（AVSpeechSynthesizer + 切句）
│   ├── CollectionStore.swift   收藏夹（增删改 / 排序 / 嵌套）
│   ├── BackupService.swift     整库 zip 导出 / 恢复（合并·覆盖）
│   ├── AnnotationStore.swift   书签/笔记/高亮/涂鸦仓库
│   ├── BookImporter.swift      导入：txt/pdf/epub/cbz/图片集
│   ├── TextEncodingDetector.swift  UTF-8/GBK/Big5/UTF-16 编码探测
│   ├── ChapterParser.swift     章节正则识别
│   ├── TxtPaginator.swift      TextKit 分页引擎
│   ├── ComicExtractor.swift    CBZ/ZIP 解压 + 自然排序
│   └── EPUBParser.swift        EPUB → 纯文本
├── Utils/                      Color+Hex、音量键监听
└── Views/
    ├── Library/                书架 / 侧栏 / 收藏夹管理 / 备份
    ├── Reader/                 阅读器（VM / TXT 分页 / TXT 滚动 / PDF / PDF 搜索 / 漫画 / 容器）
    └── Overlays/               手写层、设置面板、笔记编辑、查词、目录与搜索
```

---

## 五、已知限制（后续可优化）

- **EPUB** 采用「转纯文本」方案：保留正文与章节，不保留原书 CSS/图片。
- **CBR（RAR 漫画）** 不支持（RAR 是商业授权格式），请先转成 CBZ/ZIP。
- 上下滚动模式下，手写涂鸦锚定在「当前屏」而不是精确字符位置（分页模式下是精确到页的）。
- 超长篇（百万字以上）首次打开需要几秒分页时间，期间显示进度提示。
- 音量键翻页使用 MPVolumeView 方案，按下时音量条不会显示（这是刻意的，避免遮挡页面）。

---

## 六、重新生成 Xcode 工程（可选）

如果文件有增删，可以重新生成 `project.pbxproj`：

```bash
python3 tools/gen_xcodeproj.py
```

脚本会覆盖 `InkReader.xcodeproj/project.pbxproj`。新增 Swift 文件后记得把它加进脚本里的文件清单。

改完可以先跑一下静态自检（检查文件有没有漏登记、括号配不配平）：

```bash
python3 tools/check_sources.py
```

## 七、两个容易踩的坑

1. **Swift 的 `init(from:)` 要写在 `extension` 里。**
   写在 `struct` 本体会让编译器不再生成成员逐一初始化器（`Book(id:title:format:…)`），
   而导入器全靠它造书。`Book` / `ReadingSettings` 的容忍型解码都放在 extension 中。

2. **新字段必须同步加到容忍型解码里。**
   `Book`、`ReadingSettings` 都是逐字段 `decodeIfPresent(...) ?? 默认值`，
   用合成版 `Decodable` 的话，老存档缺一个 key 就会整个 throw，用户的书架和设置全丢。
