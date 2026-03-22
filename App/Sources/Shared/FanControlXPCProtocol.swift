import Foundation

@objc protocol FanControlXPCProtocol {
    func probeBackend(executablePath: String, withReply reply: @escaping (String?) -> Void)
    func setAuto(executablePath: String, fanIDs: [NSNumber], withReply reply: @escaping (String?) -> Void)
    func setManualRPM(executablePath: String, fanIDs: [NSNumber], rpm: NSNumber, withReply reply: @escaping (String?) -> Void)
}
