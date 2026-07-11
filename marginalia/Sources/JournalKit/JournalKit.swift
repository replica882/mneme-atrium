import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

public extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

/// 拟物手账设计系统（A-1）。真相源 `docs/design-refs/vocab-journal/design-dna.json`，
/// 视觉基准 `mockup-a.html` v6（粟粟拍过）。单词系统专用，不外溢到聊天主界面。
public enum JournalTheme {
    // 纸色阶
    public static let desk = Color(hex: 0xF6F0E7)         // 桌面底（比纸深一档，纸才浮得起）
    public static let paper = Color(hex: 0xFFFDF9)        // 纸面
    public static let paperUnder = Color(hex: 0xF8F3EA)   // 底下露出的第二张纸
    public static let tabIdle = Color(hex: 0xEFE8DC)      // 未选中标签
    public static let ink = Color(hex: 0x46413A)          // 墨水字
    public static let pencil = Color(hex: 0x8A8378)       // 铅笔灰
    public static let faint = Color(hex: 0xB3AC9F)        // 极淡字（微标签/占位）
    public static let mint = Color(hex: 0x8EBD9F)
    public static let rose = Color(hex: 0xC98A8A)
    public static let amber = Color(hex: 0xE89B47)
    public static let clay = Color(hex: 0xC97B6E)
    public static let shadowInk = Color(hex: 0x4A453D)

    // 原主库 Theme 残留收敛（开源刀1：手帐是固定纸色世界，不跟随动态主题）
    public static let wash = Color(hex: 0xE7EEEC)     // 浅灰薄荷底（原 JournalTheme.wash）
    public static let cream = Color(hex: 0xFFFBF6)    // 暖奶白（原 JournalTheme.cream）
    public static let sage = Color(red: 0.92970, green: 0.95683, blue: 0.93724)  // 原 JournalTheme.sage

    /// 字号 scale（原 Theme.F，平台分叉照搬）。
    public enum F {
        #if os(iOS)
        public static let sectionHeader: CGFloat = 16
        public static let body: CGFloat = 14
        public static let secondary: CGFloat = 13
        public static let caption: CGFloat = 11
        #else
        public static let sectionHeader: CGFloat = 13
        public static let body: CGFloat = 11
        public static let secondary: CGFloat = 10
        public static let caption: CGFloat = 9
        #endif
    }

    /// 活页行距（行系统：行高 = 格线距，字坐线上）
    public static let ruleGap: CGFloat = 30

    // 衬线系统（v3 定稿：New York 做主角）
    public static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    public static func serifItalic(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif).italic()
    }
    public static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }
}

// MARK: - 资产加载

#if os(iOS)
public typealias JournalImage = UIImage
#else
public typealias JournalImage = NSImage
#endif

/// 松散 bundle 图统一显式加载。Assets.car 并存时 Image(name)/UIImage(named:) 对松散
/// 文件的回退不可信（"看不见纹理"查了三轮的真凶候选）——contentsOfFile 直读文件系统。
public enum JournalAssets {
    public static let lace: JournalImage? = load("pixel-lace")
    /// 稀疏版（词详情页外底——密版只给 tab 外围，粟粟拍的两档）。
    public static let laceSparse: JournalImage? = load("pixel-lace-sparse")

    private static func load(_ name: String, scale: CGFloat = 1) -> JournalImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            probe(name, "bundle url MISSING")
            return nil
        }
        #if os(iOS)
        guard let data = try? Data(contentsOf: url),
              let img = UIImage(data: data, scale: scale) else {
            probe(name, "decode FAILED")
            return nil
        }
        #else
        guard let img = NSImage(contentsOf: url) else {
            probe(name, "decode FAILED")
            return nil
        }
        if scale != 1 {
            img.size = NSSize(width: img.size.width / scale, height: img.size.height / scale)
        }
        #endif
        probe(name, "ok")
        return img
    }

    /// 探针双写 console + UserDefaults（plist 可从 Mac devicectl 拉取，不依赖 attach 时机）。
    private static func probe(_ name: String, _ result: String) {
        print("[PROBE] journal asset \(name): \(result)")
        UserDefaults.standard.set(result, forKey: "journalAssetProbe.\(name)")
    }
}

/// 平台无关平铺图。
public struct TiledJournalImage: View {
    public init(image: JournalImage, opacity: Double = 1.0) {
        self.image = image; self.opacity = opacity
    }
    let image: JournalImage
    var opacity: Double = 1.0

    public var body: some View {
        #if os(iOS)
        Image(uiImage: image)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
        #else
        Image(nsImage: image)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
        #endif
    }
}

// MARK: - 纸纹

/// 纸纹已全线退役（07-10 粟粟拍板：主面素色，质感只留给胶带/星星这类小件）。
/// 组件壳保留，想回头一处改回。
public struct PaperNoise: View {
    public init(opacity: Double = 1.0) { self.opacity = opacity }
    var opacity: Double = 1.0
    public var body: some View {
        EmptyView()
    }
}

// MARK: - 纸卡

/// 纸卡：纸面 + 纸纹 + 暖灰投影 + 可选左缘玫瑰线/微旋转。描边体系在拟物层退役。
public struct PaperCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 14
    var rotation: Double = 0
    var roseEdge: Bool = false
    var shadow: PaperShadow = .medium

    public enum PaperShadow {
        case low, medium, high
        var radius: CGFloat { switch self { case .low: 3; case .medium: 8; case .high: 20 } }
        var y: CGFloat { switch self { case .low: 1; case .medium: 3; case .high: 6 } }
        var opacity: Double { switch self { case .low: 0.10; case .medium: 0.13; case .high: 0.16 } }
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(JournalTheme.paper)
                    PaperNoise()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    if roseEdge {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(JournalTheme.rose.opacity(0.45))
                            .frame(width: 1.5)
                            .padding(.vertical, 14)
                            .padding(.leading, 14)
                    }
                }
            )
            .shadow(color: JournalTheme.shadowInk.opacity(shadow.opacity),
                    radius: shadow.radius, y: shadow.y)
            .rotationEffect(.degrees(rotation))
    }
}

public extension View {
    func paperCard(cornerRadius: CGFloat = 14, rotation: Double = 0,
                   roseEdge: Bool = false,
                   shadow: PaperCardModifier.PaperShadow = .medium) -> some View {
        modifier(PaperCardModifier(cornerRadius: cornerRadius, rotation: rotation,
                                   roseEdge: roseEdge, shadow: shadow))
    }
}

// MARK: - 活页格线

/// 薄荷格线（Canvas 一次画，静态）。offset = 首条线的 y。
public struct RuledLines: View {
    public init(topOffset: CGFloat = 12) { self.topOffset = topOffset }
    var topOffset: CGFloat = 12
    public var body: some View {
        Canvas { ctx, size in
            var y = topOffset + JournalTheme.ruleGap
            var line = Path()
            while y < size.height {
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                y += JournalTheme.ruleGap
            }
            ctx.stroke(line, with: .color(JournalTheme.mint.opacity(0.24)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 玫瑰双边线（活页纸左缘）。
public struct RoseMarginLines: View {
    public init(x: CGFloat = 50) { self.x = x }
    var x: CGFloat = 50
    public var body: some View {
        Canvas { ctx, size in
            var l1 = Path(); l1.move(to: CGPoint(x: x, y: 0)); l1.addLine(to: CGPoint(x: x, y: size.height))
            var l2 = Path(); l2.move(to: CGPoint(x: x + 4, y: 0)); l2.addLine(to: CGPoint(x: x + 4, y: size.height))
            ctx.stroke(l1, with: .color(JournalTheme.rose.opacity(0.5)), lineWidth: 1)
            ctx.stroke(l2, with: .color(JournalTheme.rose.opacity(0.28)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 三孔（固定间距，不随页高拉伸）。
public struct PunchHoles: View {
    public init() {}
    public var body: some View {
        GeometryReader { geo in
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(hex: 0xFAFAF8))   // 露出的是蕾丝桌面底色
                    .frame(width: 15, height: 15)
                    .shadow(color: JournalTheme.shadowInk.opacity(0.28), radius: 1.2, y: 1)
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 0.5).offset(y: 0.5))
                    .position(x: 25, y: 88 + CGFloat(i) * (geo.size.height - 176) / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 和纸胶带

/// 胶带形（上下缘微斜的四边形，撕裁感）。
public struct TapeShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.015, y: rect.minY + rect.height * 0.07))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.08))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 和纸胶带：纯色斜纹 或 灰底波点（遮释义 v6 定稿款）。旋转由调用方加。
public struct WashiTape: View {
    public init(color: Color = JournalTheme.rose, dotted: Bool = false, width: CGFloat = 104, height: CGFloat = 30) {
        self.color = color; self.dotted = dotted; self.width = width; self.height = height
    }
    var color: Color = JournalTheme.rose
    var dotted: Bool = false
    var width: CGFloat = 104
    var height: CGFloat = 30

    public var body: some View {
        ZStack {
            TapeShape()
                .fill(dotted ? Color(hex: 0x9E988E).opacity(0.40) : color.opacity(0.42))
            if dotted {
                Canvas { ctx, size in
                    let cell: CGFloat = 24
                    var y: CGFloat = 7
                    while y < size.height {
                        var x: CGFloat = 7
                        while x < size.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 2.4, y: y - 2.4, width: 4.8, height: 4.8)),
                                     with: .color(.white.opacity(0.60)))
                            ctx.fill(Path(ellipseIn: CGRect(x: x + 9.6, y: y + 9.6, width: 3.8, height: 3.8)),
                                     with: .color(.white.opacity(0.42)))
                            x += cell
                        }
                        y += cell
                    }
                }
                .clipShape(TapeShape())
            } else {
                Canvas { ctx, size in
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var stripe = Path()
                        stripe.move(to: CGPoint(x: x, y: size.height))
                        stripe.addLine(to: CGPoint(x: x + size.height * 0.47, y: 0))
                        ctx.stroke(stripe, with: .color(.white.opacity(0.14)), lineWidth: 5)
                        x += 11
                    }
                }
                .clipShape(TapeShape())
            }
        }
        .frame(width: width, height: height)
        .shadow(color: JournalTheme.shadowInk.opacity(0.12), radius: 1.5, y: 1)
        .allowsHitTesting(dotted)   // 波点遮罩要接 tap；装饰胶带不挡点击
    }
}

// MARK: - 白色皱褶活页纸（词详情页，粟粟 ref-2 参考图同款）

/// 撕边纸形：上下两排撕孔半圆凹口（短页也整张纸，粟粟拍的）。
public struct TornPaperShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let holeR: CGFloat = 4.5
        let gap: CGFloat = 24
        let top: CGFloat = rect.minY + holeR + 1.5
        let bottom: CGFloat = rect.maxY - holeR - 1.5
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: top))
        var x = rect.minX + 16
        while x + holeR + 6 < rect.maxX {
            p.addLine(to: CGPoint(x: x - holeR, y: top))
            p.addArc(center: CGPoint(x: x, y: top), radius: holeR,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            x += gap
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: top))
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        // 底边孔排（从右往左，凹口向上=顶排的垂直镜像）
        x -= gap
        while x > rect.minX + 10 {
            p.addLine(to: CGPoint(x: x + holeR, y: bottom))
            p.addArc(center: CGPoint(x: x, y: bottom), radius: holeR,
                     startAngle: .degrees(0), endAngle: .degrees(-180), clockwise: true)
            x -= gap
        }
        p.addLine(to: CGPoint(x: rect.minX, y: bottom))
        p.closeSubpath()
        return p
    }
}

/// 白色活页纸：素白底 + 淡蓝格线 + 红双边线 + 上下撕孔（质感层已撤，粟粟拍板主面素色）。
/// ⚠️ 只作固定尺寸层用（纸固定、内容在纸上滚）——跟着超高滚动内容伸展会撞
/// Metal 纹理上限，Canvas/Image 被静默截断（07-10 断线事故）。
/// ⚠️ 纹理必须 Color.clear.overlay + clipped 约束——裸 scaledToFill 的固有尺寸
/// 会把平级 ZStack 撑超屏宽（07-10 撑宽事故）。
public struct CrumpledPaperPage: View {
    public init(marginX: CGFloat = 40, showRules: Bool = true) {
        self.marginX = marginX; self.showRules = showRules
    }
    var marginX: CGFloat = 40
    /// false = 只画纸和撕孔（格线红线由滚动内容自带——词详情"格线跟字走"）。
    var showRules: Bool = true

    public var body: some View {
        ZStack {
            TornPaperShape().fill(Color(hex: 0xFEFEFD))
            if showRules {
            Canvas { ctx, size in
                // 淡蓝格线（参考图色）
                var y: CGFloat = 30 + JournalTheme.ruleGap
                var lines = Path()
                while y < size.height - 8 {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                    y += JournalTheme.ruleGap
                }
                ctx.stroke(lines, with: .color(Color(hex: 0x9FBBDA).opacity(0.35)), lineWidth: 1)
                // 红双边线
                var m1 = Path(); m1.move(to: CGPoint(x: marginX, y: 10)); m1.addLine(to: CGPoint(x: marginX, y: size.height))
                var m2 = Path(); m2.move(to: CGPoint(x: marginX + 4, y: 10)); m2.addLine(to: CGPoint(x: marginX + 4, y: size.height))
                ctx.stroke(m1, with: .color(Color(hex: 0xC86A6A).opacity(0.55)), lineWidth: 1)
                ctx.stroke(m2, with: .color(Color(hex: 0xC86A6A).opacity(0.30)), lineWidth: 1)
            }
            .clipShape(TornPaperShape())
            .allowsHitTesting(false)
            }
        }
        .compositingGroup()
        .shadow(color: JournalTheme.shadowInk.opacity(0.14), radius: 9, y: 4)
        .accessibilityHidden(true)
    }
}

/// 随内容滚动的格线红线背景（词详情"格线跟字走"，R8）。
/// ⚠️ 单张 Canvas 跟超高内容伸展会撞 Metal 纹理上限被截断（07-10 断线事故）——
/// 分段小 Canvas 拼接（段高 = 行距整数倍，段间无缝），红线用纯色 shape 无上限。
public struct ScrollingRuledBackdrop: View {
    public init(marginX: CGFloat = 42, topOffset: CGFloat = 12) {
        self.marginX = marginX; self.topOffset = topOffset
    }
    var marginX: CGFloat = 42
    var topOffset: CGFloat = 12

    private let segmentHeight: CGFloat = 990   // 33 行 × 30

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    let count = max(1, Int(ceil((geo.size.height - topOffset) / segmentHeight)))
                    Color.clear.frame(height: topOffset)
                    ForEach(0..<count, id: \.self) { _ in
                        Canvas { ctx, size in
                            var y = JournalTheme.ruleGap
                            var lines = Path()
                            while y <= size.height {
                                lines.move(to: CGPoint(x: 0, y: y))
                                lines.addLine(to: CGPoint(x: size.width, y: y))
                                y += JournalTheme.ruleGap
                            }
                            ctx.stroke(lines, with: .color(Color(hex: 0x9FBBDA).opacity(0.35)), lineWidth: 1)
                        }
                        .frame(height: segmentHeight)
                    }
                }
                // 红双边线：纯色 shape（solid layer 不占纹理，安全全高）
                Rectangle()
                    .fill(Color(hex: 0xC86A6A).opacity(0.55))
                    .frame(width: 1)
                    .offset(x: marginX)
                Rectangle()
                    .fill(Color(hex: 0xC86A6A).opacity(0.30))
                    .frame(width: 1)
                    .offset(x: marginX + 4)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 像素蕾丝底（twinkle 字体参考图风）

/// 像素蕾丝背景：近白底 + 星花点阵 tile 平铺（静态资产，零运行时开销）。
/// sparse = 稀疏版（词详情页用），默认密版（tab 外围）。
public struct PixelLaceBackdrop: View {
    public init(sparse: Bool = false) { self.sparse = sparse }
    var sparse: Bool = false
    public var body: some View {
        ZStack {
            Color(hex: 0xFAFAF8)
            if let img = sparse ? JournalAssets.laceSparse : JournalAssets.lace {
                TiledJournalImage(image: img, opacity: 0.42)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 像素图标（小按钮统一视觉语言，跟蕾丝一家）

/// 像素风图标：bitmap 字符串（"X"=实心格），Canvas 方块填充，静态零开销。
public struct PixelIcon: View {
    public init(bitmap: [String], size: CGFloat = 15, color: Color = JournalTheme.pencil) {
        self.bitmap = bitmap; self.size = size; self.color = color
    }
    let bitmap: [String]
    var size: CGFloat = 15
    var color: Color = JournalTheme.pencil

    public var body: some View {
        Canvas { ctx, canvasSize in
            let rows = bitmap.count
            let cols = bitmap.map(\.count).max() ?? 1
            let cellW = canvasSize.width / CGFloat(cols)
            let cellH = canvasSize.height / CGFloat(rows)
            for (y, row) in bitmap.enumerated() {
                for (x, ch) in row.enumerated() where ch == "X" {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * cellW, y: CGFloat(y) * cellH,
                                         width: cellW + 0.2, height: cellH + 0.2)),
                             with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 图标库（12×12）。
public enum PixelGlyph {
    /// 喇叭 + 声波
    public static let speaker = [
        "............",
        ".....X......",
        "....XX...X..",
        "...XXX.X..X.",
        ".XXXXX..X.X.",
        ".XXXXX.X.X.X",
        ".XXXXX.X.X.X",
        ".XXXXX..X.X.",
        "...XXX.X..X.",
        "....XX...X..",
        ".....X......",
        "............",
    ]
    /// 循环（进复习牌堆）
    public static let repeatArrows = [
        "............",
        "....X.......",
        "...XXXXXX...",
        "..X.X....X..",
        "....X.....X.",
        ".X........X.",
        ".X........X.",
        ".X.....X....",
        "..X....X.X..",
        "...XXXXXX...",
        ".......X....",
        "............",
    ]
    /// 五角星空心（收生词本·未收）——Pixelarticons star (MIT) 光栅化，不自己发明形状
    public static let starOutline = [
        "..........XX..........",
        "..........XX..........",
        "........XX..XX........",
        "........XX..XX........",
        "........XX..XX........",
        "........XX..XX........",
        "XXXXXXXX......XXXXXXXX",
        "XXXXXXXX......XXXXXXXX",
        "XX..................XX",
        "XX..................XX",
        "..XX..............XX..",
        "..XX..............XX..",
        "....XX..........XX....",
        "....XX..........XX....",
        "....XX..........XX....",
        "..XX.....XXXX.....XX..",
        "..XX.....XXXX.....XX..",
        "..XX...XX....XX...XX..",
        "..XX...XX....XX...XX..",
        "..XXXXX........XXXXX..",
        "..XXXXX........XXXXX..",
    ]
    /// 五角星实心（收生词本·已收）——同源 flood fill 填充
    public static let starFilled = [
        "..........XX..........",
        "..........XX..........",
        "........XXXXXX........",
        "........XXXXXX........",
        "........XXXXXX........",
        "........XXXXXX........",
        "XXXXXXXXXXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXXXXXXXXXX",
        "..XXXXXXXXXXXXXXXXXX..",
        "..XXXXXXXXXXXXXXXXXX..",
        "....XXXXXXXXXXXXXX....",
        "....XXXXXXXXXXXXXX....",
        "....XXXXXXXXXXXXXX....",
        "..XXXXXXXXXXXXXXXXXX..",
        "..XXXXXXXXXXXXXXXXXX..",
        "..XXXXXXX....XXXXXXX..",
        "..XXXXXXX....XXXXXXX..",
        "..XXXXX........XXXXX..",
        "..XXXXX........XXXXX..",
    ]
}

// MARK: - 便签纸

/// 便签纸形（右下折角切掉）。
public struct StickyNoteShape: Shape {
    public init(fold: CGFloat = 16) { self.fold = fold }
    var fold: CGFloat = 16
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
        p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 折角小三角（翻起的那一片，比纸面深一档）。
private struct StickyFoldCorner: View {
    var fold: CGFloat = 16
    public var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: fold))
            p.addLine(to: CGPoint(x: fold, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.closeSubpath()
        }
        .fill(Color(hex: 0xEFE7D6))
        .frame(width: fold, height: fold)
        .shadow(color: JournalTheme.shadowInk.opacity(0.15), radius: 1, x: -1, y: -1)
    }
}

/// 便签纸：暖白纸 + 纸纹 + 右下折角 + 投影。笔记块 / sheet 小卡用。
public struct StickyNoteModifier: ViewModifier {
    var rotation: Double = 0
    var tone: Color = Color(hex: 0xFFFEF6)
    private let fold: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack(alignment: .bottomTrailing) {
                    StickyNoteShape(fold: fold).fill(tone)
                    PaperNoise().clipShape(StickyNoteShape(fold: fold))
                    StickyFoldCorner(fold: fold)
                }
            )
            .shadow(color: JournalTheme.shadowInk.opacity(0.13), radius: 6, y: 3)
            .rotationEffect(.degrees(rotation))
    }
}

public extension View {
    func stickyNote(rotation: Double = 0, tone: Color = Color(hex: 0xFFFEF6)) -> some View {
        modifier(StickyNoteModifier(rotation: rotation, tone: tone))
    }
}

// MARK: - 星星贴纸

public struct StarShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rOuter = min(rect.width, rect.height) / 2
        let rInner = rOuter * 0.42
        var p = Path()
        for i in 0..<10 {
            let angle = (Double(i) * 36.0 - 90) * .pi / 180
            let r = i.isMultiple(of: 2) ? rOuter : rInner
            let pt = CGPoint(x: c.x + CGFloat(cos(angle)) * r, y: c.y + CGFloat(sin(angle)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// 星星贴纸（白描边 + 投影，压角出血用）。
public struct StarSticker: View {
    public init(color: Color = JournalTheme.mint, size: CGFloat = 28, rotation: Double = 0) {
        self.color = color; self.size = size; self.rotation = rotation
    }
    var color: Color = JournalTheme.mint
    var size: CGFloat = 28
    var rotation: Double = 0

    public var body: some View {
        StarShape()
            .fill(color)
            .overlay(StarShape().stroke(Color.white, lineWidth: 1.4))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .shadow(color: JournalTheme.shadowInk.opacity(0.22), radius: 1.5, y: 1.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
