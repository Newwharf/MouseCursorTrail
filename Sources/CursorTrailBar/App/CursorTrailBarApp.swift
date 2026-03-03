//
// CursorTrailBarApp.swift
// 应用入口
//
import AppKit

@main
/// 应用入口类型。
enum CursorTrailBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
