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
        sendSignal(
            pid: pid,
            signal: SIGTERM,
            failureMessage: "終了に失敗しました"
        )
    }
    
    /// 強制終了（SIGKILL）
    static func forceTerminateProcess(pid: Int32) -> TerminationResult {
        sendSignal(
            pid: pid,
            signal: SIGKILL,
            failureMessage: "強制終了に失敗しました"
        )
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
    
    /// システムプロセスを含むグループ終了警告を表示
    static func showSystemGroupWarning(
        groupName: String,
        systemProcessCount: Int,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "システムプロセスを含むグループの終了"
        alert.informativeText = """
        「\(groupName)」にはシステムプロセスが \(systemProcessCount) 件含まれています。
        
        グループ終了を実行すると、システムが不安定になったり、
        予期しない動作が発生する可能性があります。
        
        本当に続行しますか？
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "続行")
        
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
    
    private static func sendSignal(
        pid: Int32,
        signal: Int32,
        failureMessage: String
    ) -> TerminationResult {
        let result = kill(pid, signal)
        
        if result == 0 {
            return .success
        } else if errno == EPERM {
            switch PrivilegedHelperClient.shared.sendSignal(pid: pid, signal: signal) {
            case .success(let helperErrno):
                return mapErrnoToResult(
                    helperErrno,
                    failureMessage: failureMessage
                )
            case .failure(let error):
                return .failed(error.localizedDescription)
            }
        } else if errno == ESRCH {
            return .processNotFound
        } else {
            return .failed("\(failureMessage) (errno: \(errno))")
        }
    }
    
    private static func mapErrnoToResult(
        _ errnoCode: Int32,
        failureMessage: String
    ) -> TerminationResult {
        if errnoCode == 0 {
            return .success
        } else if errnoCode == EPERM {
            return .permissionDenied
        } else if errnoCode == ESRCH {
            return .processNotFound
        } else {
            return .failed("\(failureMessage) (errno: \(errnoCode))")
        }
    }
}
