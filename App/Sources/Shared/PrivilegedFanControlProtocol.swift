import Foundation

@objc protocol PrivilegedFanControlProtocol {
    func probe(withReply reply: @escaping (String?) -> Void)
    func readFans(withReply reply: @escaping (NSData?) -> Void)
    func dumpFanModeKeys(withReply reply: @escaping (NSData?) -> Void)
    func setAuto(fanIDsCSV: NSString, withReply reply: @escaping (String?) -> Void)
    func setManualRPM(fanIDsCSV: NSString, rpm: NSNumber, withReply reply: @escaping (String?) -> Void)
#if DEBUG
    // Arbitrary SMC key I/O via the root helper — the XPC surface is
    // compiled out of Release so a misbehaving or hijacked client cannot
    // write to unrelated SMC keys (brightness, battery, charging, etc.)
    // through this helper.
    func writeRawKey(key: NSString, type: NSString, hexBytes: NSString, withReply reply: @escaping (String?) -> Void)
    func readRawKey(key: NSString, withReply reply: @escaping (NSString?, String?) -> Void)
#endif
}

func makePrivilegedFanControlInterface() -> NSXPCInterface {
    NSXPCInterface(with: PrivilegedFanControlProtocol.self)
}
