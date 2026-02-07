import Foundation
import AppKit

struct ProcessManager {
    
    enum TerminationResult {
        case success
        case permissionDenied
        case processNotFound
        case failed(String)
    }
    
    /// 通常終了（SIGTERM）
    static func terminateProcess(pid: Int32) -> TerminationResult {
        let result = kill(pid, SIGTERM)
        
        if result == 0 {
            return .success
        } else if errno == EPERM {
            return .permissionDenied
        } else if errno == ESRCH {
            return .processNotFound
        } else {
            return .failed("終了に失敗しました (errno: \(errno))")
        }
    }
    
    /// 強制終了（SIGKILL）
    static func forceTerminateProcess(pid: Int32) -> TerminationResult {
        let result = kill(pid, SIGKILL)
        
        if result == 0 {
            return .success
        } else if errno == EPERM {
            return .permissionDenied
        } else if errno == ESRCH {
            return .processNotFound
        } else {
            return .failed("強制終了に失敗しました (errno: \(errno))")
        }
    }
    
    /// システムプロセス警告を表示
    static func showSystemProcessWarning(processName: String, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "システムプロセスの終了"
        alert.informativeText = """
        「\(processName)」はシステムプロセスです。
        
        このプロセスを終了すると、システムが不安定になったり、
        予期しない動作が発生する可能性があります。
        
        本当に終了しますか？
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "終了する")
        
        let response = alert.runModal()
        completion(response == .alertSecondButtonReturn)
    }
    
    /// 終了不可プロセス警告を表示
    static func showCriticalProcessAlert(processName: String) {
        let alert = NSAlert()
        alert.messageText = "終了できないプロセス"
        alert.informativeText = """
        「\(processName)」はmacOSの重要なシステムプロセスです。
        
        このプロセスを終了すると、システムがクラッシュするか、
        強制的に再起動が必要になります。
        
        このプロセスは終了できません。
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// 終了結果のアラートを表示
    static func showResultAlert(result: TerminationResult, processName: String) {
        let alert = NSAlert()
        
        switch result {
        case .success:
            alert.messageText = "プロセスを終了しました"
            alert.informativeText = "「\(processName)」を終了しました。"
            alert.alertStyle = .informational
            
        case .permissionDenied:
            alert.messageText = "権限がありません"
            alert.informativeText = """
            「\(processName)」を終了する権限がありません。
            
            このプロセスを終了するには、管理者権限が必要な場合があります。
            """
            alert.alertStyle = .warning
            
        case .processNotFound:
            alert.messageText = "プロセスが見つかりません"
            alert.informativeText = "プロセスはすでに終了している可能性があります。"
            alert.alertStyle = .informational
            
        case .failed(let message):
            alert.messageText = "エラー"
            alert.informativeText = message
            alert.alertStyle = .critical
        }
        
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
