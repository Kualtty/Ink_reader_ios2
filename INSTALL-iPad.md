# 把墨阅装到 iPad（Windows 电脑 + 免费 Apple ID）

CI 编出来的 ipa 是**未签名**的（GitHub 上没有你的证书），iPad 不认。
所以流程是：**下载 ipa → 在 Windows 上用工具重签 → 装进 iPad**。

> **顺序很重要**：「开发者模式」平时在设置里是**看不到的**，
> 必须先用签名工具连上 iPad 装一次（这个 USB 配对动作）它才会出现。
> 所以是 先装 → 再开开发者模式 → 再点开 App，不是反过来。

---

## 第 1 步：下载 ipa

1. GitHub 打开仓库 `Ink_reader_ios2`
2. **Actions** → 点最新那次 **绿色 ✓** 的运行
3. 页面拉到最下面 **Artifacts** → `InkReader-unsigned-ipa`
4. 下载下来是个 `.zip`，解压得到 `InkReader-unsigned.ipa`

> - Artifacts 默认保留 30 天。
> - **ipa 只有 1~2 MB 是正常的**：整个 App 就是 SwiftUI 代码 + 一个小依赖，没有大资源。
>   想确认内容的话，用 7-Zip 打开 ipa，里面应该有 `Payload/InkReader.app/`，
>   再里面有 `InkReader`（无扩展名的可执行文件，最大）和 `Info.plist`。有这些就是完整的。

---

## 第 2 步：签名安装（这一步会让「开发者模式」出现）

### A. Sideloadly —— 最简单，推荐先用这个

1. 电脑装 [Sideloadly](https://sideloadly.io/)（Windows / macOS 都有，免费）
2. iPad **数据线**接电脑，解锁屏幕，弹「信任此电脑」时点信任
3. Sideloadly 里点 IPA 那一栏选中 `InkReader-unsigned.ipa`
4. 填 Apple ID（**建议专门注册一个小号**，别用主号）
   - 开了双重认证的话，密码栏要填 **App 专用密码**：
     到 [appleid.apple.com](https://appleid.apple.com) → 登录 → 「App 专用密码」→ 生成一个，16 位
5. 点 **Start**，等进度条走完（首次会慢一点）
6. 装完先**别急着点图标**，接着做第 3 步

### B. AltStore —— 可以无线续签，不用每次插线

1. Windows 装 AltServer（[altstore.io](https://altstore.io)），并用它把 AltStore 装到 iPad
2. iPad 打开 AltStore → **My Apps** → 左上角 `+` → 选那个 ipa
3. 之后只要电脑和 iPad 在**同一个 Wi-Fi**、AltServer 开着，AltStore 会自己在后台续签

### C. 巨魔 TrollStore —— 永久签名，但门槛高

只在 iPadOS **17.0 整版**（17.0.1 及以上都不行）能用。
装了之后 ipa 直接永久签名，**不用 7 天一签**，也不需要开发者模式。
先看「设置 → 通用 → 关于本机」的系统版本再决定走不走这条路。

---

## 第 3 步：打开「开发者模式」（装完之后再做）

现在去 **设置 → 隐私与安全性**，拉到**最底部**，「开发者模式」应该已经出现了：

1. 打开开关 → 弹窗提示会降低安全性 → 点 **重新启动**
2. 重启解锁后，屏幕上会弹「要打开开发者模式吗？」→ 点**打开** → 输锁屏密码

> 装完还是找不到？按顺序试：
> 1. 把「设置」App 从后台划掉再重开（这个选项要重新加载一次才刷出来）
> 2. 重启 iPad 再看
> 3. 换一根数据线 / 换个 USB 口，重新连一次 Sideloadly 让它配对
> 4. 确认系统 ≥ iPadOS 16（设置 → 通用 → 关于本机）；
>    如果 iPad 是学校/公司管理的（有 MDM 描述文件），开发者模式会被管理员锁死

---

## 第 4 步：信任证书，然后打开 App

1. 此时点桌面上的「墨阅」会提示**需要开发者模式**（没开模式的话）；
   模式开了之后如果再提示「不受信任的开发者」：
2. **设置 → 通用 → VPN 与设备管理** → 点你签名用的 Apple ID → **信任**
3. 回桌面点开「墨阅」，开始用

---

## 第 5 步：常见状况

| 现象 | 原因 | 怎么办 |
| --- | --- | --- |
| 设置里找不到「开发者模式」 | 还没和电脑配对过 | 做完第 2 步再回来看；或见第 3 步末尾的排查 |
| 点图标闪退 / 打不开 | 开发者模式没开 | 第 3 步 |
| 提示「无法验证 App」「未受信任的开发者」 | 证书没信任 | 第 4 步 |
| 用得好好的突然打不开 | 免费 Apple ID 签名 **7 天**到期 | 插电脑重签（方案 A 第 5 步重来一遍即可，不用重新编译） |
| Sideloadly 报 Apple ID 错误 | 填的是登录密码而不是 App 专用密码 | 去 appleid.apple.com 生成专用密码 |
| 装到第 4 个 App 失败 | 免费账号限 3 个 App ID | 删掉一个旧的再装 |
| 桌面图标是空白的 | 用的还是旧 ipa（9-23 之前编的没有图标） | 重新 Run workflow 下载新的 |

---

## 想要「一次签一年」/ 发给别人装

免费 Apple ID 永远是 7 天。想一劳永逸需要**付费开发者账号**（¥688/年）：

1. 拿到证书后导出 `.p12` 和 `.mobileprovision`
2. 到 GitHub 仓库 **Settings → Secrets and variables → Actions** 新建：
   - `CERTIFICATE_BASE64`（p12 的 base64）
   - `CERTIFICATE_PASSWORD`
   - `PROVISIONING_PROFILE_BASE64`
   - `EXPORT_OPTIONS_PLIST`
3. 我给工作流加一个 `-exportArchive` 的步骤，就能直接产出**已签名、1 年有效**的 ipa，
   下载下来用爱思助手 / Apple Configurator 直接装，不用每次重签。

需要的话跟我说，我把这个工作流补上（再加个 `build-signed-ipa.yml`）。
