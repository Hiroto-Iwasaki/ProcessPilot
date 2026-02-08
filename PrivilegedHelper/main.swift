import Foundation
import Darwin
import ProcessPilotCommon

final class PrivilegedHelperService: NSObject, NSXPCListenerDelegate, ProcessPilotPrivilegedHelperXPC {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: ProcessPilotPrivilegedHelperXPC.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }
    
    func sendSignal(pid: Int32, signal: Int32, withReply reply: @escaping (Int32) -> Void) {
        let result = kill(pid, signal)
        reply(result == 0 ? 0 : errno)
    }
}

let listener = NSXPCListener(machServiceName: PrivilegedHelperContract.defaultMachServiceName)
let delegate = PrivilegedHelperService()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
