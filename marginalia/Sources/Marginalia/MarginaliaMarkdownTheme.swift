import SwiftUI
import MarkdownUI
import JournalKit

extension MarkdownUI.Theme {
    /// Marginalia 手账页 Markdown 主题（墨水字 + 薄荷链接 + 玫瑰引用条）。
    static let marginalia = MarkdownUI.Theme()
        .text {
            ForegroundColor(JournalTheme.ink)
            FontSize(14.5)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.87))
            ForegroundColor(JournalTheme.ink)
            BackgroundColor(JournalTheme.desk.opacity(0.7))
        }
        .link { ForegroundColor(JournalTheme.mint) }
        .strong { FontWeight(.semibold) }
        .emphasis { FontStyle(.italic) }
        .heading1 { cfg in
            cfg.label
                .markdownTextStyle { FontSize(19); FontWeight(.bold); ForegroundColor(JournalTheme.ink) }
                .markdownMargin(top: 20, bottom: 10)
        }
        .heading2 { cfg in
            cfg.label
                .markdownTextStyle { FontSize(16.5); FontWeight(.semibold); ForegroundColor(JournalTheme.ink) }
                .markdownMargin(top: 18, bottom: 8)
        }
        .heading3 { cfg in
            cfg.label
                .markdownTextStyle { FontSize(15); FontWeight(.semibold); ForegroundColor(JournalTheme.ink) }
                .markdownMargin(top: 16, bottom: 8)
        }
        .paragraph { cfg in
            cfg.label
                .relativeLineSpacing(.em(0.42))
                .markdownMargin(top: 0, bottom: 11)
        }
        .blockquote { cfg in
            cfg.label
                .markdownTextStyle { ForegroundColor(JournalTheme.pencil); FontSize(13.5) }
                .padding(.leading, 12)
                .padding(.vertical, 4)
                .overlay(alignment: .leading) {
                    Rectangle().fill(JournalTheme.rose.opacity(0.5)).frame(width: 2.5)
                }
                .markdownMargin(top: 4, bottom: 8)
        }
        .thematicBreak {
            Rectangle()
                .fill(Color(hex: 0x9FBBDA).opacity(0.35))
                .frame(height: 0.8)
                .markdownMargin(top: 16, bottom: 16)
        }
        .list { cfg in cfg.label.markdownMargin(top: 8, bottom: 10) }
        .listItem { cfg in cfg.label.markdownMargin(top: .em(0.4)) }
}
