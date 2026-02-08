import Foundation
import ServiceManagement
import ProcessPilotCommon

enum PrivilegedHelperError: LocalizedError {
    case requiresApproval
    case registrationFailed(String)
    case xpcProxyUnavailable
    case xpcCallFailed(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return """
            権限ヘルパーの実行には管理者承認が必要です。
            システム設定のログイン項目（バックグラウンド項目）で ProcessPilot のデーモンを許可してください。
            """
        case .registrationFailed(let detail):
            return "権限ヘルパーの登録に失敗しました: \(detail)"
        case .xpcProxyUnavailable:
            return "権限ヘルパーへの接続に失敗しました。"
        case .xpcCallFailed(let detail):
            return "権限ヘルパー呼び出しでエラーが発生しました: \(detail)"
        case .timeout:
            return "権限ヘルパーが応答しませんでした。"
        }
    }
}

final class PrivilegedHelperClient {
    static let shared = PrivilegedHelperClient()
    
    private let timeoutSeconds: TimeInterval = 5
    
    private init() {}
    
    func sendSignal(pid: Int32, signal: Int32) -> Result<Int32, PrivilegedHelperError> {
        let firstAttempt = callHelper(pid: pid, signal: signal)
        switch firstAttempt {
        case .success:
            return firstAttempt
        case .failure(let error):
            guard shouldAttemptRegistration(for: error) else {
                return .failure(error)
            }
        }
        
        switch registerHelperIfNeeded() {
        case .failure(let error):
            return .failure(error)
        case .success:
            return callHelper(pid: pid, signal: signal)
        }
    }
    
    private func callHelper(pid: Int32, signal: Int32) -> Result<Int32, PrivilegedHelperError> {
        let stateLock = NSLock()
        var responseErrno: Int32?
        var responseError: PrivilegedHelperError?
        let semaphore = DispatchSemaphore(value: 0)
        
        let connection = NSXPCConnection(
            machServiceName: helperMachServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: ProcessPilotPrivilegedHelperXPC.self)
        connection.interruptionHandler = {
            stateLock.lock()
            if responseErrno == nil && responseError == nil {
                responseError = .xpcCallFailed("接続が中断されました。")
                semaphore.signal()
            }
            stateLock.unlock()
        }
        connection.invalidationHandler = {
            stateLock.lock()
            if responseErrno == nil && responseError == nil {
                responseError = .xpcCallFailed("接続が無効化されました。")
                semaphore.signal()
            }
            stateLock.unlock()
        }
        connection.resume()
        
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            stateLock.lock()
            responseError = .xpcCallFailed(error.localizedDescription)
            semaphore.signal()
            stateLock.unlock()
        }) as? ProcessPilotPrivilegedHelperXPC else {
            connection.invalidate()
            return .failure(.xpcProxyUnavailable)
        }
        
        proxy.sendSignal(pid: pid, signal: signal) { errnoCode in
            stateLock.lock()
            responseErrno = errnoCode
            semaphore.signal()
            stateLock.unlock()
        }
        
        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        connection.invalidate()
        
        if waitResult == .timedOut {
            return .failure(.timeout)
        }
        
        if let responseError {
            return .failure(responseError)
        }
        
        guard let responseErrno else {
            return .failure(.xpcProxyUnavailable)
        }
        
        return .success(responseErrno)
    }
    
    private func shouldAttemptRegistration(for error: PrivilegedHelperError) -> Bool {
        switch error {
        case .xpcProxyUnavailable, .xpcCallFailed:
            return true
        case .timeout, .requiresApproval, .registrationFailed:
            return false
        }
    }
    
    private func registerHelperIfNeeded() -> Result<Void, PrivilegedHelperError> {
        guard #available(macOS 13.0, *) else {
            return .failure(.registrationFailed("macOS 13 以降が必要です。"))
        }
        
        let service = SMAppService.daemon(plistName: helperDaemonPlistName)
        
        if service.status == .enabled {
            return .success(())
        }
        
        do {
            try service.register()
        } catch {
            let nsError = error as NSError
            if nsError.code == Int(kSMErrorAlreadyRegistered) {
                return .success(())
            }
            if nsError.code == Int(kSMErrorLaunchDeniedByUser) || service.status == .requiresApproval {
                return .failure(.requiresApproval)
            }
            
            let detail = "\(nsError.localizedDescription) (domain: \(nsError.domain), code: \(nsError.code))"
            return .failure(.registrationFailed(detail))
        }

        switch service.status {
        case .enabled:
            return .success(())
        case .requiresApproval:
            return .failure(.requiresApproval)
        case .notRegistered, .notFound:
            return .failure(.registrationFailed("デーモンが有効化されませんでした。"))
        @unknown default:
            return .failure(.registrationFailed("不明なサービス状態です。"))
        }
    }
    
    private var helperMachServiceName: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: PrivilegedHelperContract.appInfoKeyMachServiceName) as? String,
           !value.isEmpty {
            return value
        }
        
        return PrivilegedHelperContract.defaultMachServiceName
    }
    
    private var helperDaemonPlistName: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: PrivilegedHelperContract.appInfoKeyDaemonPlistName) as? String,
           !value.isEmpty {
            return value
        }
        
        return PrivilegedHelperContract.defaultDaemonPlistName
    }
}
