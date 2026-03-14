import Foundation

enum WaveformModel {
    static func smooth(_ value: Float, previous: Float, alpha: Float = 0.45) -> Float {
        return (alpha * value) + ((1 - alpha) * previous)
    }
}
