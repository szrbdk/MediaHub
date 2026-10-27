import Foundation

struct PlaybackTimeline {
    var duration: Double = 0
    var elapsed: Double = 0
    var timestamp: Double = 0
    var rate: Double = 0
    var isValid = false
    var isAdvancing: Bool { isValid && rate > 0 }

    init() {}

    init(payload: [String: Any], hasMedia: Bool, now: Double = Date().timeIntervalSince1970) {
        guard hasMedia,
              let durationMicros = payload["durationMicros"] as? Double,
              let elapsedMicros = payload["elapsedTimeMicros"] as? Double,
              durationMicros.isFinite, durationMicros > 0, elapsedMicros.isFinite else { return }
        duration = durationMicros / 1_000_000
        elapsed = max(0, elapsedMicros / 1_000_000)
        let epoch = (payload["timestampEpochMicros"] as? Double).map { $0 / 1_000_000 }
        timestamp = epoch?.isFinite == true ? epoch! : now
        let playbackRate = payload["playbackRate"] as? Double ?? 1
        rate = (payload["playing"] as? Bool == true && playbackRate.isFinite) ? max(0, playbackRate) : 0
        isValid = true
    }

    func position(at now: Double) -> Double {
        min(duration, max(0, elapsed + max(0, now - timestamp) * rate))
    }

    func seekMicroseconds(fraction: Double) -> Int64? {
        guard isValid, fraction.isFinite, duration.isFinite, duration > 0 else { return nil }
        let micros = min(1, max(0, fraction)) * duration * 1_000_000
        guard micros.isFinite, micros < Double(Int64.max) else { return nil }
        return Int64(micros)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds < Double(Int.max) else { return "–:––" }
        let value = Int(max(0, seconds))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
