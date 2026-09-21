//  墨阅 InkReader · InkReader/Services/ShareCrypto.swift
//  功能：共享加密 —— PBKDF2-HMAC-SHA256 派生密钥 + AES-GCM 加解密。
//  要点：PBKDF2 是手写实现（60k 轮），刻意没用 CommonCrypto，省掉桥接头。

import CryptoKit
import Foundation

/// 局域网共享用的对称加密
///
/// 两端各自输入同一个密码，用 PBKDF2 推出 AES-GCM 密钥，
/// 每条消息都是一次独立的 seal（nonce 随机），所以中继/抓包只看得到密文。
///
/// 没有用 CommonCrypto 的 CCKeyDerivationPBKDF：那个在 Swift 里要挂桥接头，
/// 这里直接用 CryptoKit 的 HMAC<SHA256> 手写了 PBKDF2，省一个依赖。
enum ShareCrypto {
    /// 固定 salt：两端只靠密码对齐，salt 直接写死在协议里
    static let salt = Data("inkreader-lan-share-v1".utf8)
    static let iterations = 60_000
    static let keyByteCount = 32

    static func key(password: String) -> SymmetricKey {
        SymmetricKey(data: pbkdf2SHA256(
            password: Data(password.utf8),
            salt: salt,
            iterations: iterations,
            keyByteCount: keyByteCount
        ))
    }

    static func seal<T: Encodable>(_ value: T, password: String) throws -> Data {
        let plain = try JSONEncoder().encode(value)
        let box = try AES.GCM.seal(plain, using: key(password: password))
        guard let combined = box.combined else { throw ShareError.sealFailed }
        return combined
    }

    static func open<T: Decodable>(_ type: T.Type,
                                   from data: Data,
                                   password: String) throws -> T {
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: key(password: password))
        return try JSONDecoder().decode(type, from: plain)
    }

    // MARK: - PBKDF2-HMAC-SHA256

    static func pbkdf2SHA256(password: Data,
                             salt: Data,
                             iterations: Int,
                             keyByteCount: Int) -> Data {
        let hmacKey = SymmetricKey(data: password)
        var derived = Data()
        var counter: UInt32 = 1

        while derived.count < keyByteCount {
            var input = salt
            var be = counter.bigEndian
            let bytes = withUnsafeBytes(of: &be) { Array($0) }
            input.append(contentsOf: bytes.reversed())     // PBKDF2 要求大端计数

            var u = Data(HMAC<SHA256>.authenticationCode(for: input, using: hmacKey))
            var t = u
            var round = 1
            while round < iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: hmacKey))
                t = xor(t, u)
                round += 1
            }
            derived.append(t)
            counter += 1
        }
        return Data(derived.prefix(keyByteCount))
    }

    private static func xor(_ a: Data, _ b: Data) -> Data {
        let count = min(a.count, b.count)
        var out = Data(count: count)
        let aStart = a.startIndex
        let bStart = b.startIndex
        for i in 0..<count {
            out[i] = a[aStart + i] ^ b[bStart + i]
        }
        return out
    }
}

enum ShareError: LocalizedError {
    case sealFailed
    case passwordMismatch
    case notShared
    case tooLarge
    case badAddress

    var errorDescription: String? {
        switch self {
        case .sealFailed: return "加密失败"
        case .passwordMismatch: return "密码不对，或者对方不是墨阅"
        case .notShared: return "对方没有共享这本书"
        case .tooLarge: return "这本书太大了，暂时传不了"
        case .badAddress: return "地址或端口不对"
        }
    }
}
