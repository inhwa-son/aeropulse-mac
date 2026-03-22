import Foundation

final class FanControlServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener.service()

    func run() {
        listener.delegate = self
        listener.resume()
        RunLoop.current.run()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let exported = FanControlService()
        newConnection.exportedInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
        newConnection.exportedObject = exported
        newConnection.resume()
        return true
    }
}

@main
struct ControlServiceMain {
    static func main() {
        let delegate = FanControlServiceDelegate()
        delegate.run()
    }
}
