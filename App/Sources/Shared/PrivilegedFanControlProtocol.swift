import Foundation

@objc protocol PrivilegedFanControlProtocol {
    func probe(withReply reply: @escaping (String?) -> Void)
    func readFans(withReply reply: @escaping (NSData?) -> Void)
    func dumpFanModeKeys(withReply reply: @escaping (NSData?) -> Void)
    func setAuto(fanIDsCSV: NSString, withReply reply: @escaping (String?) -> Void)
    func setManualRPM(fanIDsCSV: NSString, rpm: NSNumber, withReply reply: @escaping (String?) -> Void)
}

func makePrivilegedFanControlInterface() -> NSXPCInterface {
    NSXPCInterface(with: PrivilegedFanControlProtocol.self)
}
