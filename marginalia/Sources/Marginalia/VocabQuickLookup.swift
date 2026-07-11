import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// R3.4 快速查词：不想考古那么重的时候——系统词典（iPhone 内置牛津英汉，
/// 设置→通用→词典 免费下载，离线正版）+ 单词发音。
enum VocabQuickLookup {

    #if os(macOS)
    /// macOS 直接唤起词典 app。
    static func openSystemDictionary(word: String) {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        if let url = URL(string: "dict://\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif
}

#if os(iOS)
/// 系统词典 sheet（UIReferenceLibraryViewController）：词典没下载时它自带引导 UI。
struct DictionarySheet: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ vc: UIReferenceLibraryViewController, context: Context) {}
}
#endif
