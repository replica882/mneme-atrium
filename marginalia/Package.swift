// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Marginalia",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // 手账设计系统（零依赖可独立引用）：纸页/书签tab/和纸胶带/星星贴纸/像素图标/像素蕾丝/衬线 token
        .library(name: "JournalKit", targets: ["JournalKit"]),
        // 单词手账全套：刷词 / SM-2 复习 / 生词本 / 统计 / tag / 内嵌词典 / 发音
        .library(name: "Marginalia", targets: ["Marginalia"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "JournalKit",
            resources: [.process("Resources")]
        ),
        .target(
            name: "Marginalia",
            dependencies: [
                "JournalKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            resources: [.process("Resources")]
        ),
    ]
)
