//
// LaunchAtLoginManager.swift
// MVC: 系统服务（开机自启）
//
import ServiceManagement

@MainActor
/// 开机自启管理器（基于 `SMAppService.mainApp`）。
final class LaunchAtLoginManager {
    /// 设置是否开机自启。
    /// - Returns: 操作是否执行成功。
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// 读取系统层面的当前注册状态。
    func currentStatus() -> SMAppService.Status? {
        guard #available(macOS 13.0, *) else { return nil }
        return SMAppService.mainApp.status
    }

    /// 当前是否处于已启用开机自启状态。
    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}
