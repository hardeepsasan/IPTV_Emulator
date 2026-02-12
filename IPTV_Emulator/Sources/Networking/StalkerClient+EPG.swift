import Foundation

extension StalkerClient {
    
    // MARK: - EPG API
    
    public func getEPG(channelId: String, period: Int = 24) async throws -> [EPGEvent] {
        if isDemoMode { return [] }
        
        // Stalker Action: get_epg_info
        // Period is in hours usually
        
        // Note: fetch is now internal, allowing access from this extension
        let json = try await fetch(action: "get_epg_info", type: "itv", params: [
            "period": String(period),
            "ch_id": channelId
        ])
        
        print("DEBUG: getEPG RAW: \(json)")
        
        if let root = json as? [String: Any],
           let js = root["js"] as? [String: Any],
           let dataList = js["data"] as? [[String: Any]] {
            
            let data = try JSONSerialization.data(withJSONObject: dataList)
            // Sometimes IDs in EPG are integers
            var events = try JSONDecoder().decode([EPGEvent].self, from: data)
            
            // Sort by time using raw values to avoid isolation warnings
            events.sort { (Double($0.time) ?? 0) < (Double($1.time) ?? 0) }
            
            return events
        }
        
        return []
    }
    
    public func getShortEPG(channelId: String) async throws -> [EPGEvent] {
         if isDemoMode { return [] }

         // Stalker Action: get_short_epg
         // Returns current and next event usually
         
         let json = try await fetch(action: "get_short_epg", type: "itv", params: [
             "ch_id": channelId
         ])
         
         print("DEBUG: getShortEPG RAW: \(json)")
         
         // Fix: Short EPG returns 'js' as the direct array of events, unlike 'get_epg_info'
         if let root = json as? [String: Any] {
             var dataList: [[String: Any]]? = nil
             
             if let directArray = root["js"] as? [[String: Any]] {
                 dataList = directArray
             } else if let jsDict = root["js"] as? [String: Any], let nestedData = jsDict["data"] as? [[String: Any]] {
                 dataList = nestedData
             }
             
             if let eventsData = dataList {
                 let data = try JSONSerialization.data(withJSONObject: eventsData)
                 var events = try JSONDecoder().decode([EPGEvent].self, from: data)
                 
                 // Sort by time
                 events.sort { (Double($0.time) ?? 0) < (Double($1.time) ?? 0) }
                 
                 return events
             }
         }
         
         return []
     }
}
