//  墨阅 InkReader · InkReader/Utils/VolumeKeyObserver.swift
//  功能：音量键翻页 —— 用隐藏的 MPVolumeView + KVO 捕获系统音量变化，转成翻页事件。
//  要点：只是辅助手段，主交互仍是点击与滑动。

import AVFoundation
import MediaPlayer
import UIKit

/// 音量键翻页监听（使用 MPVolumeView + KVO 的通用方案）
@MainActor
final class VolumeKeyObserver {
    static let shared = VolumeKeyObserver()

    private let session = AVAudioSession.sharedInstance()
    private var volumeView = MPVolumeView()
    private var slider: UISlider?
    private var observation: NSKeyValueObservation?
    private var baseline: Float = 0.5
    private var isObserving = false

    var onUp: (() -> Void)?
    var onDown: (() -> Void)?

    private init() {}

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard !isObserving else { return }
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // 静音模式下仍可继续监听
        }
        baseline = session.outputVolume

        volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        volumeView.showsRouteButton = false
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            window.addSubview(volumeView)
        }
        slider = volumeView.subviews.compactMap { $0 as? UISlider }.first

        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, change in
            guard let self, let volume = change.newValue else { return }
            if volume > self.baseline + 0.001 {
                self.onUp?()
            } else if volume < self.baseline - 0.001 {
                self.onDown?()
            }
            self.slider?.value = self.baseline
        }
        isObserving = true
    }

    private func stop() {
        guard isObserving else { return }
        observation?.invalidate()
        observation = nil
        volumeView.removeFromSuperview()
        isObserving = false
    }
}
