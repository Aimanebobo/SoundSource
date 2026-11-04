import SwiftUI

/// SoundSource-style horizontal slider: thin track, live level meter inside the track, white knob.
/// When `maxValue > 1` the last 20 % of the track is a boost zone with a detent at 100 %.
struct VolumeSlider: View {
    @Binding var value: Float
    var maxValue: Float = 1
    var defaultValue: Float = 1
    var level: Float = 0
    var showsMeter = true
    var isEnabled = true
    var isDimmed = false
    var onEditingEnded: (() -> Void)?

    private let knobSize: CGFloat = 13
    private let trackHeight: CGFloat = 6
    private let boostStart: CGFloat = 0.8

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - knobSize, 1)
            let position = sliderPosition(of: value)
            ZStack(alignment: .leading) {
                track(width: travel, position: position)
                    .padding(.horizontal, knobSize / 2)
                Circle()
                    .fill(isEnabled ? Color.white : Color.white.opacity(0.35))
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                    .offset(x: position * travel)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        var newValue = sliderValue(at: (drag.location.x - knobSize / 2) / travel)
                        if maxValue > 1, abs(newValue - 1) < 0.04 { newValue = 1 }   // detent at 100 %
                        value = (newValue * 100).rounded() / 100
                    }
                    .onEnded { _ in onEditingEnded?() }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                value = defaultValue
                onEditingEnded?()
            })
        }
        .frame(height: 18)
        .opacity(isDimmed ? 0.5 : 1)
        .allowsHitTesting(isEnabled)
    }

    private func track(width: CGFloat, position: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Theme.track)
            if maxValue > 1 {
                Rectangle()
                    .fill(Theme.warning.opacity(0.16))
                    .frame(width: width * (1 - boostStart))
                    .offset(x: width * boostStart)
            }
            Rectangle()
                .fill(isEnabled ? Theme.accent.opacity(0.6) : Color.white.opacity(0.18))
                .frame(width: width * position)
            if showsMeter, level > 0.001 {
                Theme.meter
                    .frame(width: width)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * CGFloat(min(level, 1)))
                    }
                    .opacity(0.95)
            }
        }
        .frame(width: width, height: trackHeight)
        .clipShape(Capsule())
        .overlay(alignment: .leading) {
            if maxValue > 1 {
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 1, height: trackHeight + 5)
                    .offset(x: width * boostStart)
            }
        }
    }

    private func sliderPosition(of value: Float) -> CGFloat {
        guard maxValue > 1 else { return CGFloat(min(max(value / maxValue, 0), 1)) }
        if value <= 1 { return CGFloat(max(value, 0)) * boostStart }
        return boostStart + CGFloat(min((value - 1) / (maxValue - 1), 1)) * (1 - boostStart)
    }

    private func sliderValue(at position: CGFloat) -> Float {
        let p = min(max(position, 0), 1)
        guard maxValue > 1 else { return Float(p) * maxValue }
        if p <= boostStart { return Float(p / boostStart) }
        return 1 + Float((p - boostStart) / (1 - boostStart)) * (maxValue - 1)
    }
}

/// Centre-detented slider for balance (-1 … +1).
struct BalanceSlider: View {
    @Binding var value: Float
    var isEnabled = true

    private let knobSize: CGFloat = 11

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - knobSize, 1)
            let position = CGFloat((min(max(value, -1), 1) + 1) / 2)
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Rectangle()
                        .fill(Theme.accent.opacity(0.7))
                        .frame(width: abs(position - 0.5) * travel)
                        .offset(x: min(position, 0.5) * travel)
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1)
                        .offset(x: travel / 2)
                }
                .frame(width: travel, height: 4)
                .clipShape(Capsule())
                .padding(.horizontal, knobSize / 2)
                Circle()
                    .fill(isEnabled ? Color.white : Color.white.opacity(0.35))
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                    .offset(x: position * travel)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let p = Float(min(max((drag.location.x - knobSize / 2) / travel, 0), 1))
                var newValue = p * 2 - 1
                if abs(newValue) < 0.06 { newValue = 0 }
                value = (newValue * 100).rounded() / 100
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = 0 })
        }
        .frame(height: 16)
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Vertical EQ band slider (-12 … +12 dB) with a fill from the 0 dB line.
struct EQBandSlider: View {
    @Binding var value: Float
    var isEnabled = true

    private let knobSize: CGFloat = 11
    private let range = EQBands.range

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.height - knobSize, 1)
            let span = range.upperBound - range.lowerBound
            let position = CGFloat(1 - (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span)
            let knobY = position * travel
            let midY = travel / 2
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Theme.track)
                    .frame(width: 4, height: travel)
                    .offset(y: knobSize / 2)
                Rectangle()
                    .fill(isEnabled ? Theme.accent : Color.white.opacity(0.3))
                    .frame(width: 4, height: abs(knobY - midY))
                    .offset(y: min(knobY, midY) + knobSize / 2)
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 12, height: 1)
                    .offset(y: midY + knobSize / 2)
                Circle()
                    .fill(isEnabled ? Color.white : Color.white.opacity(0.55))
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                    .offset(y: knobY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let p = Float(1 - min(max((drag.location.y - knobSize / 2) / travel, 0), 1))
                var newValue = range.lowerBound + p * span
                newValue = (newValue * 2).rounded() / 2      // 0.5 dB steps
                if abs(newValue) < 0.4 { newValue = 0 }
                value = newValue
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = 0 })
        }
    }
}
