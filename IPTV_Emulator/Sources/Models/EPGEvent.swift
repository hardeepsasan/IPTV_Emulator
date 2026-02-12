import Foundation

public struct EPGEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let time: String 
    public let timeTo: String 
    public let duration: String
    public let descr: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case time
        case timeTo = "time_to"
        case duration
        case descr
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // ID: Handle String or Int
        if let idInt = try? container.decode(Int.self, forKey: .id) {
            id = String(idInt)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        
        name = try container.decode(String.self, forKey: .name)
        
        // Time: Handle String or Int
        if let tInt = try? container.decode(Int.self, forKey: .time) {
            time = String(tInt)
        } else {
            time = try container.decode(String.self, forKey: .time)
        }
        
        // TimeTo: Handle String or Int
        if let tInt = try? container.decode(Int.self, forKey: .timeTo) {
            timeTo = String(tInt)
        } else {
            timeTo = try container.decode(String.self, forKey: .timeTo)
        }
        
        // Duration: Handle String or Int
        if let dInt = try? container.decode(Int.self, forKey: .duration) {
            duration = String(dInt)
        } else {
            duration = try container.decode(String.self, forKey: .duration)
        }
        
        descr = try container.decodeIfPresent(String.self, forKey: .descr)
    }
    
    // Helper to get formatted Time
    public var startTimeDate: Date? {
        if let interval = TimeInterval(time) {
            return Date(timeIntervalSince1970: interval)
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current // Or server timezone if known
        return formatter.date(from: time)
    }
    
    public var endTimeDate: Date? {
        if let interval = TimeInterval(timeTo) {
            return Date(timeIntervalSince1970: interval)
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: timeTo)
    }
    
    public var formattedTimeRange: String {
        guard let start = startTimeDate, let end = endTimeDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}
