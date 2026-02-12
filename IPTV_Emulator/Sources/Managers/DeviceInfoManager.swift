import Foundation

class DeviceInfoManager {
    static let shared = DeviceInfoManager()
    
    // UserDefaults Keys (Must match AppStorage in IPTVEmulatorApp)
    private let kMacAddress = "settings_mac_address"
    private let kSerialNumber = "settings_serial_number"
    private let kDeviceId = "settings_device_id"
    private let kDeviceId2 = "settings_device_id2"
    private let kSignature = "settings_signature"
    private let kUserAgent = "settings_user_agent"
    
    private init() {}
    
    func ensureIdentityExists() {
        let defaults = UserDefaults.standard
        
        // 1. MAC Address
        if defaults.string(forKey: kMacAddress) == nil {
            let newMac = generateVirtualMAC()
            defaults.set(newMac, forKey: kMacAddress)
            print("DeviceInfoManager: Generated New Virtual MAC: \(newMac)")
        }
        
        // 2. Serial Number
        if defaults.string(forKey: kSerialNumber) == nil {
            let newSerial = generateSerialNumber()
            defaults.set(newSerial, forKey: kSerialNumber)
        }
        
        // 3. Device IDs
        if defaults.string(forKey: kDeviceId) == nil {
            defaults.set(UUID().uuidString.uppercased(), forKey: kDeviceId)
        }
        
        if defaults.string(forKey: kDeviceId2) == nil {
            defaults.set(UUID().uuidString.uppercased(), forKey: kDeviceId2)
        }
        
        // 4. Signature (Keep default or randomize? Randomizing for safety)
        if defaults.string(forKey: kSignature) == nil {
            let newSig = generateSignature()
            defaults.set(newSig, forKey: kSignature)
        }
        
        // 5. User Agent (Default to Modern)
        if defaults.string(forKey: kUserAgent) == nil {
            defaults.set(StalkerClient.defaultUserAgent, forKey: kUserAgent)
        }
    }
    
    // MARK: - Generators
    
    func generateVirtualMAC() -> String {
        // Prefix: 00:1A:79 (MAG Default)
        let prefix = "00:1A:79"
        let suffix = (0..<3).map { _ in String(format: "%02X", Int.random(in: 0...255)) }.joined(separator: ":")
        return "\(prefix):\(suffix)"
    }
    
    private func generateSerialNumber() -> String {
        // Format: Random 13 chars alphanumeric
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<13).map { _ in letters.randomElement()! })
    }
    
    private func generateSignature() -> String {
        // Format: Random 64 chars hex
        let hex = "0123456789ABCDEF"
        return String((0..<64).map { _ in hex.randomElement()! })
    }
}
