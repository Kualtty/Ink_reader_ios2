//  墨阅 InkReader · InkReader/Views/Overlays/SettingsPanel.swift
//  功能：阅读设置面板 —— 主题色板、字号 / 行距滑杆、对齐、翻页方向、自动翻页速度、漫画模式与方向。
//  要点：改动即时生效并落盘。

import AVFoundation
import SwiftUI
import UIKit

struct SettingsPanel: View {
    @ObservedObject var vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    private let speedPresets: [Double] = [3, 5, 8, 12, 20, 30]

    /// 列表只留中英文，否则系统里装了几十种语音会把 Picker 撑爆
    private var speechVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh") || $0.language.hasPrefix("en") }
            .sorted { lhs, rhs in
                lhs.language == rhs.language
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhs.language < rhs.language
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: 排版
                Section("排版") {
                    SliderRow(title: "字号", value: $vm.settings.fontSize, range: 12...40, step: 1) {
                        "\(Int(vm.settings.fontSize))"
                    }
                    SliderRow(title: "行距", value: $vm.settings.lineSpacing, range: 0...30, step: 1) {
                        "\(Int(vm.settings.lineSpacing))"
                    }
                    SliderRow(title: "字距", value: $vm.settings.characterSpacing, range: 0...8, step: 0.2) {
                        String(format: "%.1f", vm.settings.characterSpacing)
                    }
                    SliderRow(title: "段距", value: $vm.settings.paragraphSpacing, range: 0...40, step: 1) {
                        "\(Int(vm.settings.paragraphSpacing))"
                    }
                    SliderRow(title: "页边距", value: $vm.settings.horizontalMargin, range: 8...60, step: 1) {
                        "\(Int(vm.settings.horizontalMargin))"
                    }

                    Picker("对齐", selection: $vm.settings.alignment) {
                        ForEach(TextAlignOption.allCases) { option in
                            Text(option.name).tag(option)
                        }
                    }

                    Toggle("粗体", isOn: $vm.settings.isBold)

                    Picker("字体", selection: $vm.settings.fontName) {
                        ForEach(ReaderFonts.available, id: \.name) { font in
                            Text(font.display).tag(font.name)
                        }
                    }
                }

                // MARK: 外观
                Section("背景与文字") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ReaderTheme.allCases) { theme in
                                ThemeSwatch(
                                    theme: theme,
                                    isSelected: vm.settings.theme == theme,
                                    background: Color(hex: theme.defaultBackgroundHex),
                                    foreground: Color(hex: theme.defaultForegroundHex)
                                ) {
                                    vm.settings.theme = theme
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    ColorPicker("背景色", selection: Binding(
                        get: { Color(hex: vm.settings.customBackgroundHex) },
                        set: { vm.settings.customBackgroundHex = $0.hexString; vm.settings.theme = .custom }
                    ))

                    ColorPicker("文字色", selection: Binding(
                        get: { Color(hex: vm.settings.customForegroundHex) },
                        set: { vm.settings.customForegroundHex = $0.hexString; vm.settings.theme = .custom }
                    ))
                }

                // MARK: 翻页
                Section("翻页") {
                    Picker("方向", selection: $vm.settings.direction) {
                        ForEach(PageTurnDirection.allCases) { direction in
                            Label(direction.title, systemImage: direction.icon).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("横屏双页（PDF / 漫画）", isOn: $vm.settings.doublePageSpread)
                    Toggle("音量键翻页", isOn: $vm.settings.volumeKeyTurn)
                    Toggle("显示页码", isOn: $vm.settings.showPageIndicator)
                }

                // MARK: 自动翻页
                Section("自动翻页") {
                    SliderRow(title: "速度", value: $vm.settings.autoPlaySpeed, range: 1...60, step: 0.5) {
                        String(format: "%.1f 秒/页", vm.settings.autoPlaySpeed)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(speedPresets, id: \.self) { preset in
                                Button {
                                    vm.settings.autoPlaySpeed = preset
                                } label: {
                                    Text("\(Int(preset))s")
                                        .font(.subheadline)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(abs(vm.settings.autoPlaySpeed - preset) < 0.1
                                                      ? Color.accentColor
                                                      : Color(.systemGray5))
                                        )
                                        .foregroundStyle(abs(vm.settings.autoPlaySpeed - preset) < 0.1
                                                         ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Toggle("屏幕常亮", isOn: $vm.settings.keepScreenOn)
                }

                // MARK: 播读
                Section("播读") {
                    SliderRow(title: "语速", value: $vm.settings.speechRate, range: 0.1...1.0, step: 0.05) {
                        String(format: "%.2f×", vm.settings.speechRate)
                    }
                    .onChange(of: vm.settings.speechRate) { _ in vm.speechRateDidChange() }

                    Picker("语音", selection: $vm.settings.speechVoiceId) {
                        Text("自动（按内容挑）").tag("")
                        ForEach(speechVoices, id: \.identifier) { voice in
                            Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                        }
                    }

                    Button {
                        vm.speakSelection("这是一句试听，用来确认当前的语速和语音。")
                    } label: {
                        Label("试听一句", systemImage: "speaker.wave.2")
                    }
                } footer: {
                    Text("可用的语音取决于 iPad 在「设置 → 辅助功能 → 朗读内容 → 声音」里下载了哪些。列表只列中英文，没看到想要的先去系统里下载。")
                }

                // MARK: 预览
                Section("预览") {
                    Text("这是一行示例文字，用来预览当前的字体、字号、行距与配色效果。")
                        .font(Font(vm.settings.uiFont))
                        .lineSpacing(vm.settings.lineSpacing)
                        .foregroundStyle(vm.settings.textColor)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(vm.settings.backgroundColor)
                        .cornerRadius(8)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        vm.settingsDidChange()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear { vm.settingsDidChange() }
    }
}

// MARK: - 滑块行

private struct SliderRow<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    let display: () -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

// MARK: - 主题色块

private struct ThemeSwatch: View {
    let theme: ReaderTheme
    let isSelected: Bool
    let background: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(background)
                        .frame(width: 62, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color(.systemGray4), lineWidth: isSelected ? 2.5 : 1)
                        )
                    Text("Aa")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(foreground)
                }
                Text(theme.name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
