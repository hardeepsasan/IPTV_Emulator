import Foundation
import CryptoKit

struct IdentityGenerator {
    
    struct Identity {
        let serialNumber: String
        let deviceId: String
        let deviceId2: String
        let signature: String
    }
    
    /// Generates deterministic identity values based on the MAC address.
    /// - Parameter mac: The MAC address string (e.g. "00:1A:79:...")
    /// - Returns: Tuple containing generated SN, DeviceID, DeviceID2, Signature
    static func generate(for mac: String) -> Identity {
        let cleanMac = mac.uppercased().replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = cleanMac.isEmpty ? "DEFAULT_KEY" : cleanMac
        
        return Identity(
            serialNumber: generateSerial(from: key),
            deviceId: generateHash(from: key),
            deviceId2: generateHash(from: key + "_SALT_DEV2"),
            signature: generateHash(from: key + "_SIG_SALT")
        )
    }
    
    private static func generateHash(from input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02X", $0) }.joined()
    }
    
    private static func generateSerial(from input: String) -> String {
        // Serial numbers are often shorter, alphanumeric.
        // We'll take the first 13 chars of the hash to match the default length (13)
        // Default: 686F73JAE8F30
        let hash = generateHash(from: "SN_" + input)
        let prefix = String(hash.prefix(13))
        return prefix.uppercased()
    }
}
