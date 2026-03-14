import Foundation

struct WaveformInputMetrics {
    let rms: Float
    let peak: Float
    let sampleDuration: Float
}

struct WaveformModel {
    private var displayLevel: Float = 0
    private var noiseFloorDb: Float = -60
    private var speechReferenceDb: Float = -24
    private var gateOpen = false
    private var gateHoldRemaining: Float = 0

    mutating func reset() {
        displayLevel = 0
        noiseFloorDb = -60
        speechReferenceDb = -24
        gateOpen = false
        gateHoldRemaining = 0
    }

    mutating func process(_ input: WaveformInputMetrics) -> Float {
        let sampleDuration = max(input.sampleDuration, 1 / 120)
        let rmsDb = Self.decibels(for: input.rms)
        let peakDb = Self.decibels(for: input.peak)

        updateNoiseFloor(using: rmsDb)
        let openedThisFrame = updateGate(rmsDb: rmsDb, peakDb: peakDb, sampleDuration: sampleDuration)
        updateSpeechReference(using: rmsDb, sampleDuration: sampleDuration, openedThisFrame: openedThisFrame)

        let visualizationGainDb = Self.clamp(-22 - speechReferenceDb, lower: -6, upper: 12)
        let floorDb = noiseFloorDb + 12
        let rangeDb: Float = 34

        let body = Self.clamp((rmsDb + visualizationGainDb - floorDb) / rangeDb)
        let transient = Self.clamp((peakDb + visualizationGainDb - floorDb) / rangeDb)

        var rawLevel = gateOpen ? ((0.88 * body) + (0.12 * transient)) : 0
        rawLevel = pow(rawLevel, 0.82)

        displayLevel = Self.follow(
            current: displayLevel,
            target: rawLevel,
            attack: 0.035,
            release: 0.10,
            sampleDuration: sampleDuration
        )

        if !gateOpen && displayLevel < 0.03 {
            displayLevel = 0
        }

        return Self.clamp(displayLevel)
    }

    private mutating func updateNoiseFloor(using rmsDb: Float) {
        guard !gateOpen || rmsDb < noiseFloorDb + 6 else {
            return
        }

        let blend: Float = rmsDb < noiseFloorDb ? 0.18 : 0.04
        noiseFloorDb = Self.clamp(noiseFloorDb + ((rmsDb - noiseFloorDb) * blend), lower: -72, upper: -45)
    }

    private mutating func updateSpeechReference(using rmsDb: Float, sampleDuration: Float, openedThisFrame: Bool) {
        guard gateOpen else {
            speechReferenceDb = Self.follow(
                current: speechReferenceDb,
                target: -24,
                attack: 4,
                release: 4,
                sampleDuration: sampleDuration
            )
            return
        }

        if openedThisFrame {
            speechReferenceDb = min(speechReferenceDb, rmsDb)
        }

        speechReferenceDb = Self.follow(
            current: speechReferenceDb,
            target: rmsDb,
            attack: 0.25,
            release: 0.75,
            sampleDuration: sampleDuration
        )
    }

    private mutating func updateGate(rmsDb: Float, peakDb: Float, sampleDuration: Float) -> Bool {
        let openThreshold = noiseFloorDb + 12
        let closeThreshold = noiseFloorDb + 8
        let triggerDb = max(rmsDb, peakDb)

        if gateOpen {
            if triggerDb >= closeThreshold {
                gateHoldRemaining = 0.08
            } else {
                gateHoldRemaining -= sampleDuration
                if gateHoldRemaining <= 0 {
                    gateOpen = false
                    gateHoldRemaining = 0
                }
            }
            return false
        }

        guard triggerDb >= openThreshold else {
            return false
        }

        gateOpen = true
        gateHoldRemaining = 0.08
        return true
    }

    private static func decibels(for amplitude: Float) -> Float {
        let clampedAmplitude = max(amplitude, 0.000_000_1)
        return max(-90, 20 * log10(clampedAmplitude))
    }

    private static func follow(
        current: Float,
        target: Float,
        attack: Float,
        release: Float,
        sampleDuration: Float
    ) -> Float {
        let timeConstant = target > current ? attack : release
        guard timeConstant > 0 else {
            return target
        }

        let coefficient = exp(-sampleDuration / timeConstant)
        return (coefficient * current) + ((1 - coefficient) * target)
    }

    private static func clamp(_ value: Float, lower: Float = 0, upper: Float = 1) -> Float {
        return min(max(value, lower), upper)
    }
}
