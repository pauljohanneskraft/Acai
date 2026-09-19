import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension AppAddress {
    @MainActor
    func copyLinkToPasteboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #else
        UIPasteboard.general.url = url
        #endif
    }
}
