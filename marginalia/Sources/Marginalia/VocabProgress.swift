import Foundation
import SwiftData

/// 学习状态枚举。raw value 跟原 NGSL JS 兼容（"known" / "slow" / "unknown"），
/// 导出 CSV/Anki TSV 时直接写 raw，跟原 NGSL 工具链无缝对接。
public enum VocabStatus: String, Codable, CaseIterable {
    /// 认识（key 1）—— 秒懂。
    case known
    /// 反应慢（key 2）—— 见过但卡顿。
    case slow
    /// 不认识（key 3）—— 完全没见过。
    case unknown
}

/// 单词学习进度。**不带 `profileId`**——词汇量是粟粟本身的属性，跨楼层共享是设计。
///
/// 这是项目里唯一不带 profileId 的 @Model。
/// 例外原因见 `.claude/rules/swiftdata.md` 末尾说明。
///
/// 一个 word 至多一条记录（业务侧保证，无 unique constraint）。
@Model
public final class VocabProgress {
    /// 词面，跟 `VocabWord.word` 对应。业务侧保证 unique。
    var word: String = ""

    /// 状态原始字符串（兼容原 NGSL CSV/Anki 字段）。
    /// 业务侧用 `status` 计算属性，不直接读这个。
    var statusRaw: String = ""

    /// 标记时计时秒数（从首次显示到标记的耗时）。导出 CSV 时一并带走。
    var seconds: Double = 0

    /// 用户自定义备注（写在卡片下方 TextField，mark 时一并保存）。
    var note: String = ""

    /// 标记时间，最近一次 mark 的时间戳（不参与导出，但留着做"今日复习"用）。
    var markedAt: Date = Date()

    // CR-3 书词打通 + AI 注解（port 时白纸定对，全 optional 老数据零负担）：
    /// 收词出处（阅读器选词入库时写），复用 bookRef 格式 `<safeName>#chapter<N>`。nil = 词库刷词。
    var sourceBookRef: String? = nil
    /// 出处原句快照（失锚降级展示用）。
    var anchorText: String? = nil
    /// AI 注解（问{{char}} 回答回填）。与用户 note 分离——**不可删对方笔迹**：无删除入口。
    var aiNote: String? = nil
    var aiNoteAt: Date? = nil

    public init(word: String, status: VocabStatus, seconds: Double, note: String = "", markedAt: Date = Date()) {
        self.word = word
        self.statusRaw = status.rawValue
        self.seconds = seconds
        self.note = note
        self.markedAt = markedAt
    }

    /// 类型安全的状态访问。
    var status: VocabStatus {
        get { VocabStatus(rawValue: statusRaw) ?? .unknown }
        set { statusRaw = newValue.rawValue }
    }
}
