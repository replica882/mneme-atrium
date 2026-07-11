import Foundation

/// 「复习」模块的调度内核（SM-2 变体）。纯函数无副作用——将来换 FSRS 只换这里。
enum SM2Rating: String, Codable { case again, hard, good }

/// 题型：认读（先猜后看）/ 拼写 / 造句。强度随卡片成熟度爬坡。
enum VocabExercise: String, Codable { case read, spell, sentence }

struct SM2State: Equatable {
    var ease: Double
    var intervalDays: Double
    var reps: Int
    var lapses: Int
}

enum SM2 {
    static let minEase = 1.3

    static func review(_ s: SM2State, rating: SM2Rating) -> SM2State {
        var n = s
        switch rating {
        case .good:
            n.intervalDays = s.reps == 0 ? 1 : (s.reps == 1 ? 3 : s.intervalDays * s.ease)
            n.reps += 1
        case .hard:
            n.intervalDays = max(1, s.intervalDays * 1.2)
            n.ease = max(minEase, s.ease - 0.15)
            n.reps += 1
        case .again:
            n.intervalDays = 1
            n.ease = max(minEase, s.ease - 0.2)
            n.reps = 0
            n.lapses += 1
        }
        return n
    }

    static func nextDue(after s: SM2State, from now: Date) -> Date {
        now.addingTimeInterval(s.intervalDays * 86_400)
    }

    /// 题型阶梯：越熟越难。遗忘（again 清 reps）自动跌回认读重学。
    static func exercise(reps: Int, intervalDays: Double) -> VocabExercise {
        if reps < 2 { return .read }
        if intervalDays >= 7 { return .sentence }
        return .spell
    }
}
