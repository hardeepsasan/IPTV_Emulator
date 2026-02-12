import Foundation
import UIKit // for UIImage/NSCache
import ImageIO
import SwiftUI
import Combine

public enum ConnectionStatus: String {
    case idle
    case connecting
    case connected
    case failed
}

public enum StalkerError: Error {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case authFailed
    case noToken
}

public class StalkerClient: NSObject, ObservableObject, URLSessionDelegate {
    public static let shared = StalkerClient(macAddress: "00:00:00:00:00:00") // Added for Swift interoperability and easy access
    
    @Published var movies: [Movie] = []
    // Cache is now persistent - REMOVED @Published to prevent UI Storms
    public var movieCache: [String: Movie] = [:] 
    
    // UI-Optimized Observable for checks
    @Published public var cacheCount: Int = 0
    
    @Published public var categoryMetadata: [String: Int] = [:] // Cache total_items count
    @Published public var cacheSizeString: String = "..." // Displayable cache size
    public var vodInfoCache: [String: Movie] = [:] // Cache for detailed VOD info
    private var vodTasks: [String: Task<Movie?, Error>] = [:] // Deduplication for in-flight requests
    @Published public var hasShownDisclaimer = false // Global state for "Loading..." screen
    @Published public var subscriptionExpiration: Date? // Parsed from get_profile
    @Published public var connectionStatus: ConnectionStatus = .idle
    @Published public var isConnected: Bool = true
    private var networkCancellable: AnyCancellable?
    
    // User Activity Backoff
    private var lastUIInteraction: Date = .distantPast
    
    // Hybrid Fetch Deduplication
    private var hybridFetchTasks: [String: Task<[Movie], Error>] = [:]
    
    // Category Cache
    private var categoryCache: [String: [Category]] = [:]

    // Last Index Time
    public var lastIndexDate: Date? {
        get {
            guard let interval = UserDefaults.standard.object(forKey: "last_index_timestamp") as? TimeInterval else { return nil }
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "last_index_timestamp")
                objectWillChange.send()
            }
        }
    }
    
    public var lastIndexDuration: TimeInterval {
        return UserDefaults.standard.double(forKey: "last_index_duration")
    }
    
    public var lastIndexDurationString: String {
        let duration = lastIndexDuration
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else if duration < 3600 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            return String(format: "%dh %dm", hours, minutes)
        }
    }
    
    public var macAddress: String
    public var portalURL: URL
    
    // Demo Mode Flag
    public let isDemoMode: Bool
    
    @Published public private(set) var token: String?
    
    // Deduplication Task
    private var authTask: Task<Void, Error>?
    
    public var isAuthenticated: Bool {
        return token != nil
    }
    private var session: URLSession! // Implicitly unwrapped to allow self capture in init
    
    // Configuration (Dynamic)
    public var userAgent: String
    public var serialNumber: String
    public var deviceId: String
    public var deviceId2: String
    public var signature: String
    
    // Captured User-Agent from working Smart STB app (Original / Legacy)
    public static let legacyUserAgent = "Mozilla/5.0 (Unknown; Linux) AppleWebKit/538.1 (KHTML, like Gecko) MAG200 stbapp ver: 4 rev: 734 Mobile Safari/538.1"
    
    // Updated User-Agent (MAG322 / Modern)
    public static let defaultUserAgent = "Mozilla/5.0 (Unknown; Linux) AppleWebKit/538.1 (KHTML, like Gecko) MAG322 stbapp ver: 5 rev: 230 Mobile Safari/538.1"
    
    // New User-Agent (MAG324)
    public static let mag324UserAgent = "Mozilla/5.0 (Unknown; Linux) AppleWebKit/538.1 (KHTML, like Gecko) MAG324 stbapp ver: 5 rev: 230 Mobile Safari/538.1"
    
    // CAPTURED DEVICE IDENTITY (Defaults from Smart STB)
    public static let defaultSerialNumber = "686F73JAE8F30"
    public static let defaultDeviceId = "2734F8111495CB904C3045D58C6EF37BD0F19084F7528F3DAE455287E1688031"
    public static let defaultDeviceId2 = "BF73E1F44C0DB1F39A183B9CCB6340ED5897A73EF78606D5DF2180CC4888562D"
    public static let defaultSignature = "63A32EB6C1F804FD0621B840341C12CEDC5F6AFCFC98F0F4C1576BB0A3C8115A"
    
    // UPDATED: Using the Final Redirect URL found in packet capture
    // old: http://ipro.gol.ci
    
    // MARK: - Smart URL Resolver
    /// Follows HTTP redirects to find the real portal URL (e.g. ipro.gol.ci -> ipro4k.rocd.cc)
    public static func resolveURL(_ rawURL: String) async -> String {
        var urlStr = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlStr.lowercased().hasPrefix("http") {
             urlStr = "http://" + urlStr
        }
        
        guard let url = URL(string: urlStr) else { return rawURL }
        
        print("Resolver: Checking \(url)...")
        var request = URLRequest(url: url)
        request.httpMethod = "GET" // HEAD often fails on these portals, use GET
        request.timeoutInterval = 15
        request.setValue(StalkerClient.defaultUserAgent, forHTTPHeaderField: "User-Agent") // Mimic STB
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, let finalURL = httpResp.url {
                
                // CRITICAL: Check if we redirected OR just upgraded scheme (http -> https)
                let hostChanged = (finalURL.host != url.host)
                let schemeChanged = (finalURL.scheme != url.scheme)
                let pathChanged = (finalURL.path != url.path && finalURL.path != "/")
                
                if hostChanged || schemeChanged || pathChanged {
                    print("Resolver: Redirect Detected! \(url) -> \(finalURL)")
                    
                    // Reconstruct Root if we hit a specific file like /index.html
                    // But usually we want the full base.
                    // If we redirected to `https://host/stalker_portal/c/login.html` we want `https://host/` or `https://host/stalker_portal`
                    
                    var components = URLComponents(url: finalURL, resolvingAgainstBaseURL: true)
                    
                    // Clean up common "login" or UI paths to find the base.
                    // If we get redirected to `/stalker_portal/c/`, the actual BASE for the API is likely the root of that.
                    // We want to return `https://ipro4k.rocd.cc` so the Prober finds `/stalker_portal`.
                    
                    var cleanPath = components?.path ?? ""
                    
                    if let range = cleanPath.range(of: "/stalker_portal") {
                        cleanPath = String(cleanPath[..<range.lowerBound])
                    }
                    if let range = cleanPath.range(of: "/c/") {
                        cleanPath = String(cleanPath[..<range.lowerBound])
                    }
                    
                    components?.path = cleanPath
                    components?.query = nil
                    
                    // Clean trailing slash
                    var newRoot = components?.string ?? rawURL
                    if newRoot.hasSuffix("/") { newRoot.removeLast() }
                    
                    print("Resolver: Resolved Base URL: \(newRoot)")
                    return newRoot
                }
            }
        } catch {
            print("Resolver: Failed to resolve \(rawURL): \(error)")
        }
        
        return rawURL
    }

    public init(portalURL: String = "https://ipro4k.rocd.cc", 
                macAddress: String,
                serialNumber: String = StalkerClient.defaultSerialNumber,
                deviceId: String = StalkerClient.defaultDeviceId,
                deviceId2: String = StalkerClient.defaultDeviceId2,
                signature: String = StalkerClient.defaultSignature,
                userAgent: String = StalkerClient.defaultUserAgent) {
        
        // Check for Demo Mode from Arguments OR URL Scheme
        let isMockScheme = portalURL.lowercased().hasPrefix("mock://")
        self.isDemoMode = ProcessInfo.processInfo.arguments.contains("-demoMode") || isMockScheme
        
        if self.isDemoMode {
            print("🚀 DEMO MODE ACTIVE: Using local mock data.")
        }
        
        // Ensure scheme is present (if not mock)
        var sanitizedURL = portalURL
        if !isMockScheme && !sanitizedURL.lowercased().hasPrefix("http://") && !sanitizedURL.lowercased().hasPrefix("https://") {
            sanitizedURL = "http://" + sanitizedURL
        }
        
        // Determine final URL first to be used in both Property and Headers
        let finalURL: URL
        if let url = URL(string: sanitizedURL) {
            finalURL = url
        } else {
            finalURL = URL(string: "https://ipro4k.rocd.cc")!
        }
        
        self.portalURL = finalURL
        self.macAddress = macAddress
        self.serialNumber = serialNumber
        self.deviceId = deviceId
        self.deviceId2 = deviceId2
        self.signature = signature
        self.userAgent = userAgent
        
        super.init() // Required for NSObject
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60 // Increased to 60s for stability
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = false // Disable to prevent indefinite retries on protocol errors
        config.httpMaximumConnectionsPerHost = 20 // Match our Image Semaphore limit (was 4)

        
        // Detect Model for X-User-Agent
        let model: String
        if userAgent.contains("MAG324") {
            model = "MAG324"
        } else if userAgent.contains("MAG322") {
            model = "MAG322"
        } else {
            model = "MAG200"
        }
        
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "X-User-Agent": "Model: \(model); Link: Ethernet", // Updated Link to Ethernet as per capture
            "Referer": finalURL.appendingPathComponent("stalker_portal/c/index.html").absoluteString,
            "Accept": "application/json, text/plain, */*", // Capture has text/plain
            "X-Requested-With": "XMLHttpRequest", // Critical for blocking UI redirects
            "Accept-Language": "en-US,en;q=0.9", // Capture has 0.9
            "Accept-Encoding": "gzip, deflate"
        ]
        
        // Inject MAC cookie
        // Capture CONFIRMS: mac=00%3A1A... (Encoded) and other fields are empty
        let lowerMac = macAddress.lowercased()
        let encodedMac = lowerMac.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics) ?? lowerMac
        
        let macCookie = HTTPCookie(properties: [
            .domain: finalURL.host ?? "",
            .path: "/",
            .name: "mac",
            .value: encodedMac, // Encoded
            .secure: "TRUE",
            .expires: Date(timeIntervalSinceNow: 31536000)
        ])
        
        let storage = HTTPCookieStorage.shared
        if let cookie = macCookie {
            storage.setCookie(cookie)
        }
        // Capture had empty values for these, attempting to match
        if let langCookie = HTTPCookie(properties: [.domain: finalURL.host ?? "", .path: "/", .name: "stb_lang", .value: "", .secure: "TRUE"]),
           let tzCookie = HTTPCookie(properties: [.domain: finalURL.host ?? "", .path: "/", .name: "timezone", .value: "", .secure: "TRUE"]) {
            storage.setCookie(langCookie)
            storage.setCookie(tzCookie)
        }
        
        config.httpCookieStorage = storage
        config.httpCookieAcceptPolicy = .always
        
        // Delegate allows us to bypass SSL errors (like Proxy certificates)
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // Start Cache Load Immediately
        self.cacheLoadTask = Task { [weak self] in
            guard let self = self else { return }
            if self.isDemoMode {
                // Pre-load mock cache in demo mode
                await MainActor.run {
                    var mockCache: [String: Movie] = [:]
                    DemoData.mockMovies.forEach { mockCache[$0.id] = $0 }
                    DemoData.mockSeries.forEach { mockCache[$0.id] = $0 }
                    self.movieCache = mockCache
                    self.cacheCount = mockCache.count
                }
            } else {
                await self.loadCacheFromDisk()
            }
        }
        
        // Initialize Network Monitor integration
        self.networkCancellable = NetworkMonitor.shared.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                self?.isConnected = connected
                if !connected {
                    print("StalkerClient: Network Lost (Protocol Level).")
                    // "Smart Sync" Logic:
                    // If we are currently indexing, the indexer loop will catch the error eventually.
                    // But we can also proactively pause or flag things here if needed.
                } else {
                    print("StalkerClient: Network Restored. Attempting to resume Indexer...")
                    // Auto-Resume / Smart Sync:
                    // If the previous index failed (or was interrupted), index_completed_successfully will be false.
                    // Calling buildSearchIndex(force: false) will detect this partial state and resume.
                    Task {
                        // Small delay to let connection stabilize
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                        await self?.buildSearchIndex(force: false)
                    }
                }
            }
    }
    
    // MARK: - iOS Configuration & Login Support
    
    /// Updates the client configuration at runtime (used by iOS Login Screen)
    public func configure(url: String, mac: String) {
        // 1. Sanitize URL
        var sanitizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sanitizedURL.lowercased().hasPrefix("http://") && !sanitizedURL.lowercased().hasPrefix("https://") {
            sanitizedURL = "http://" + sanitizedURL
        }
        
        // 2. Update Properties
        if let newURL = URL(string: sanitizedURL) {
            self.portalURL = newURL
        }
        self.macAddress = mac.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 3. Reset Session & Cookies with new MAC
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 20
        
        // Headers
        let model = "MAG250" // Default for generic
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "X-User-Agent": "Model: \(model); Link: Ethernet",
            "Referer": self.portalURL.appendingPathComponent("stalker_portal/c/index.html").absoluteString,
            "Accept": "application/json, text/plain, */*",
            "X-Requested-With": "XMLHttpRequest",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept-Encoding": "gzip, deflate"
        ]
        
        // Cookies
        let lowerMac = self.macAddress.lowercased()
        let encodedMac = lowerMac.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics) ?? lowerMac
        
        let macCookie = HTTPCookie(properties: [
            .domain: self.portalURL.host ?? "",
            .path: "/",
            .name: "mac",
            .value: encodedMac,
            .secure: "TRUE",
            .expires: Date(timeIntervalSinceNow: 31536000)
        ])
        
        let storage = HTTPCookieStorage.shared
        if let cookie = macCookie {
            storage.setCookie(cookie)
        }
        config.httpCookieStorage = storage
        config.httpCookieAcceptPolicy = .always
        
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        print("StalkerClient Re-Configured: URL=\(self.portalURL) MAC=\(self.macAddress)")
    }
    
    /// Triggers authentication flow (used by iOS Login Screen)
    public func login(completion: @escaping (Bool, String?) -> Void) {
        // Reset state
        self.token = nil
        self.authTask = nil 
        
        Task {
            do {
                try await self.authenticate()
                await MainActor.run {
                    completion(true, nil)
                }
            } catch {
                await MainActor.run {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    /// Resets authentication state and clears session (used for Logout)
    public func logout() {
        print("StalkerClient: Logging out and resetting authentication state.")
        self.token = nil
        self.hasShownDisclaimer = false
        self.subscriptionExpiration = nil
        self.authTask = nil
        
        // Clear cookies for the current portal
        let storage = HTTPCookieStorage.shared
        if let cookies = storage.cookies(for: portalURL) {
            for cookie in cookies {
                storage.deleteCookie(cookie)
            }
        }
    }
    
    // MARK: - Concurrency Limiter
    // Limit to 4 concurrent requests to prevent "Protocol not available" / socket exhaustion
    private let networkSemaphore = AsyncSemaphore(value: 4)
    
    /// Throttled Network Request Wrapper
    private func throttledData(for request: URLRequest) async throws -> (Data, URLResponse) {
        await networkSemaphore.wait()
        // defer cannot await, so we execute the signal in a Task to return the semaphore
        defer {
            Task {
                await networkSemaphore.signal()
            }
        }
        
        // CANCELLATION CHECK: If task was cancelled while waiting, abort immediately.
        try Task.checkCancellation()
        
        return try await session.data(for: request)
    }

    // INTERNAL HELPER: Simple Async Semaphore
    private actor AsyncSemaphore {
        private var value: Int
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(value: Int) {
            self.value = value
        }

        func wait() async {
            if value > 0 {
                value -= 1
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func signal() {
            if !waiters.isEmpty {
                let waiter = waiters.removeFirst()
                waiter.resume()
            } else {
                value += 1
            }
        }
    }
    
    // MARK: - Cache Sync
    private var cacheLoadTask: Task<Void, Never>?
    
    public func ensureCacheLoaded() async {
        _ = await cacheLoadTask?.value
    }
    
    // MARK: - URLSessionDelegate (SSL Bypass)
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // DEVELOPMENT ONLY: Blindly accept all certificates to bypass Proxy/SSL issues
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
     public func authenticate() async throws {
         // DEMO MODE BYPASS
         if isDemoMode {
             print("Authentication bypassed (Demo Mode)")
             await MainActor.run { self.connectionStatus = .connected }
             return
         }

         // 1. Check if already authenticated
         if token != nil { return }
         
         // 2. Check if authentication is already in progress
         if let existingTask = authTask {
             return try await existingTask.value
         }
         
         // 3. Start new authentication task
         let task = Task {
             await MainActor.run { self.connectionStatus = .connecting }
             try await performAuthentication()
             await MainActor.run { self.connectionStatus = .connected }
         }
         
         authTask = task
         
         // 4. Await and Clean up
         do {
             try await task.value
             authTask = nil
         } catch {
             await MainActor.run { self.connectionStatus = .failed }
             authTask = nil
             throw error
         }
     }

    // ... (rest of authentication methods)
    


     private func performAuthentication() async throws {
         // Strategy: Match Capture Exactly
         
         let lowerMac = macAddress.lowercased()
         let encodedMac = lowerMac.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics) ?? lowerMac
         
        // Strategy: Dynamic Path Discovery
        // Many providers use /stalker_portal/, but some use root / or /c/ or /mag/
        // We will probe specifically for `server/api/load_js.php` returning Javascript (not HTML)
        
        // 1. Define Candidates
        let candidates = ["stalker_portal", "", "c", "mag"]
        var validBasePath: String? = nil
        
        print("Starting Path Discovery for: \(portalURL.absoluteString)")
        
        for candidate in candidates {
            // Construct probe URL: [Host]/[Candidate]/server/api/load_js.php
            let probePath = candidate.isEmpty ? "server/api/load_js.php" : "\(candidate)/server/api/load_js.php"
            let probeURL = portalURL.appendingPathComponent(probePath)
            
            print("Probing: \(probeURL.absoluteString)")
            
            var probeReq = URLRequest(url: probeURL)
            probeReq.httpMethod = "GET"
            let cookieHeaderPre = "mac=\(lowerMac); stb_lang=en; timezone=Europe/Kiev"
            probeReq.setValue(cookieHeaderPre, forHTTPHeaderField: "Cookie")
            
            do {
                let (data, response) = try await session.data(for: probeReq)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    if let body = String(data: data, encoding: .utf8) {
                        // Check if it is valid JS and NOT HTML
                        // load_js.php usually returns `var stb ...` or empty JS, not `<!DOCTYPE`
                        if !body.contains("<!DOCTYPE") && !body.contains("<html") && !body.contains("<script") {
                             print("✅ Valid Base Path Found: '\(candidate)'")
                             validBasePath = candidate
                             break // Stop searching
                        } else {
                             print("❌ Probe returned HTML (Login Page)")
                        }
                    }
                } else {
                    print("❌ Probe Failed (Status: \((response as? HTTPURLResponse)?.statusCode ?? 0))")
                }
            } catch {
                print("❌ Probe Error: \(error.localizedDescription)")
            }
        }
        
        // Default to stalker_portal if all fail (fallback behavior)
        let basePath = validBasePath ?? "stalker_portal"
        print("Using Base Path: '\(basePath)'")
        
        // Construct paths based on discovery
        let handshakePath = basePath.isEmpty ? "server/load.php" : "\(basePath)/server/load.php"
        let authEndpoint = portalURL.appendingPathComponent(handshakePath)
        
        // Update Referer dynamically for this session if we could (Ideally we'd update config, but session is immutable)
        // For now, we trust the discovered path for the URL.
        
        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: true)!
        
        components.queryItems = [
            URLQueryItem(name: "type", value: "stb"),
            URLQueryItem(name: "action", value: "handshake"),
            URLQueryItem(name: "token", value: ""),
            URLQueryItem(name: "mac", value: lowerMac),
            URLQueryItem(name: "stb_type", value: "MAG322"),
            URLQueryItem(name: "sn", value: serialNumber),
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "device_id2", value: deviceId2),
            URLQueryItem(name: "signature", value: signature)
        ]
        
        // Force %3A encoding for MAC in URL if URLComponents didn't do it
        var urlString = components.url!.absoluteString
        if let range = urlString.range(of: "mac=\(lowerMac)") {
             urlString.replaceSubrange(range, with: "mac=\(encodedMac)")
        }
         
         var request = URLRequest(url: URL(string: urlString)!)
         request.httpMethod = "GET"
         
         // Header 'Cookie' is set automatically by URLSession from the storage we initialized
         // But we can check or force it if needed. For now, trusting the storage+config.
         
         // FORCE COOKIE (Critical Fix: Try RAW MAC with colons)
         let cookieHeader = "mac=\(lowerMac); stb_lang=en; timezone=Europe/Kiev"
         request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
         
         
         print("URL: \(request.url?.absoluteString ?? "N/A")")
         
         let (data, response) = try await throttledData(for: request)
         
         // Log Response Headers
         if let httpResp = response as? HTTPURLResponse {
             print("Handshake Headers: \(httpResp.allHeaderFields)")
         }
         
         if let responseString = String(data: data, encoding: .utf8) {
              print("Handshake Response Length: \(responseString.count)")
              
              // Check for JSON first
              if let data = responseString.data(using: .utf8),
                 let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                 let js = json["js"] as? [String: Any],
                 let newToken = js["token"] as? String {
                  await MainActor.run { self.token = newToken }
                  print("Authenticated via JSON! Token: \(self.token ?? "N/A")")
                  try await getProfile()
                  return
              }

              // If HTML, try to scrape
              print("JSON failed, attempting to scrape token from HTML...")
              let patterns = [
                  "access_token\\s*=\\s*['\"]([^'\"]+)['\"]",
                  "token\\s*:\\s*['\"]([^'\"]+)['\"]",
                  "var\\s+token\\s*=\\s*['\"]([^'\"]+)['\"]"
              ]
              
              for pattern in patterns {
                  if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                     let match = regex.firstMatch(in: responseString, options: [], range: NSRange(location: 0, length: responseString.count)),
                     let range = Range(match.range(at: 1), in: responseString) {
                      let foundToken = String(responseString[range])
                      print("Scraped Token! [\(foundToken)] using pattern: \(pattern)")
                      await MainActor.run { self.token = foundToken }
                      try await getProfile()
                      return
                  }
              }
              
              // If we are here, we failed to find a token.
              print("No token found. Attempting stateless fetch with Bearer MAC...")
              await MainActor.run { self.token = lowerMac } // Force token to be MAC
              try await getProfile() 
              return
         }
         
         guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
             throw StalkerError.authFailed
         }
         
         // Strict JSON parse
         do {
             if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let js = json["js"] as? [String: Any],
                let newToken = js["token"] as? String {
                 self.token = newToken
                 print("Authenticated! Token: \(self.token ?? "N/A")")
                 try await getProfile()
             } else {
                  throw StalkerError.authFailed
             }

         } catch {
              print("JSON Decode failed: \(error)")
              // SMART RETRY: If we failed to parse JSON (likely HTML login page), check if the URL needs resolving
              // This handles the case where users have a stuck "bad" URL in settings.
              if let dataStr = String(data: data, encoding: .utf8), dataStr.contains("<!DOCTYPE") || dataStr.contains("<html") {
                   print("Authentication failed with HTML. Attempting Smart URL Resolution...")
                   let currentURLStr = self.portalURL.absoluteString
                   let resolved = await StalkerClient.resolveURL(currentURLStr)
                   
                   if resolved != currentURLStr {
                       print("Smart Retry: URL changed from \(currentURLStr) to \(resolved). Updating Settings and Retrying...")
                       
                       // 1. Update internal state
                       if let newURL = URL(string: resolved) {
                           self.portalURL = newURL
                       }
                       
                       // 2. Persist to Settings (Critical for next launch)
                       UserDefaults.standard.set(resolved, forKey: "settings_portal_url")
                       
                       // 3. Retry Authentication (One-time recursion)
                       // Clear current task to allow re-entry
                       self.authTask = nil
                       try await self.authenticate()
                       return
                   }
              }
              
              throw StalkerError.decodingError(error)
         }
     }
    
    private func getProfile() async throws {
        // We capture text first to debug
        let res = try await fetchRaw(action: "get_profile", type: "stb")
        
        // Validate JSON
        do {
            if let json = try JSONSerialization.jsonObject(with: res) as? [String: Any],
               let js = json["js"] as? [String: Any] {
                
                print("GetProfile Success JSON: \(js)")
                
                // Parse Expiration Date
                // Format: "2026-03-04 20:05:47"
                if let expireStr = js["expire_billing_date"] as? String {
                     let formatter = DateFormatter()
                     formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                     if let date = formatter.date(from: expireStr) {
                         print("Subscription Expires: \(date)")
                         await MainActor.run { self.subscriptionExpiration = date }
                     }
                }
            }
        } catch {
            if let str = String(data: res, encoding: .utf8) {
                print("GetProfile FAILED (Not JSON): \(str)")
            }
            throw StalkerError.decodingError(error)
        }
    }
    
    // MARK: - Generic Fetch
    private func fetchRaw(action: String, type: String, params: [String: String] = [:]) async throws -> Data {
        // LAZY AUTH: Ensure we have a token before proceeding (unless in demo mode)
        if !isDemoMode && token == nil {
            print("StalkerClient: No token for '\(action)'. Triggering lazy authentication...")
            try await authenticate()
        }
        
        let currentToken = token ?? ""
        let lowerMac = macAddress.lowercased()
        let encodedMac = lowerMac.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics) ?? lowerMac
        
        let endpoint = portalURL.appendingPathComponent("stalker_portal/server/load.php")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)!
        
        // STANDARD STALKER PARAMS (Must match handshake identity)
        var queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "mac", value: lowerMac),
            URLQueryItem(name: "sn", value: serialNumber),
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "device_id2", value: deviceId2),
            URLQueryItem(name: "signature", value: signature)
        ]
        
        // Add Token if present (Stalker usually wants it in query)
        if !currentToken.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: currentToken))
        }
        
        for (key, value) in params {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        
        components.queryItems = queryItems
        
        // Force encoded MAC replacement if needed
        var urlString = components.url!.absoluteString
        if let range = urlString.range(of: "mac=\(lowerMac)") {
             urlString.replaceSubrange(range, with: "mac=\(encodedMac)")
        }
        
        var request = URLRequest(url: URL(string: urlString)!)
        
        // Some portals check Bearer, some check query param. We do both to be safe.
        // UDPATE: Reverted removal of Bearer header. It IS required for VOD.
        // It also seems required for ITV (based on recent failure without it).
        if !currentToken.isEmpty {
             request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")
        }
        
        // FORCE COOKIE
        let cookieHeader = "mac=\(lowerMac); stb_lang=en; timezone=Europe/Kiev"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        
        print("API Request: \(action) -> \(request.url?.absoluteString ?? "N/A")")
        
        let (data, _) = try await throttledData(for: request)
        return data
    }
    
    func fetch(action: String, type: String, params: [String: String] = [:]) async throws -> Any {
        let data = try await fetchRaw(action: action, type: type, params: params)
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            return json
        } catch {
            if let str = String(data: data, encoding: .utf8) {
                print("JSON Error for \(action) type=\(type): \(str)")
            }
            throw error
        }
    }
    
    // MARK: - Content API
    
    public func getCategories(type: String = "vod") async throws -> [Category] {
        if isDemoMode {
             // Return Mock Categories
             return await MainActor.run { DemoData.mockCategories }
        }

        // 1. Check Cache
        if let cached = categoryCache[type] {
            // print("StalkerClient: Returning cached categories for \(type)")
            return cached
        }

        // Stalker Action: get_categories for VOD, get_genres for ITV
        let action = (type == "itv") ? "get_genres" : "get_categories"
        
        let json = try await fetch(action: action, type: type) 
        
        // Parse: usually { "js": [ { "id": "1", "title": "...", ... } ] }
        if let root = json as? [String: Any],
           let js = root["js"] as? [[String: Any]] {
            
            let data = try JSONSerialization.data(withJSONObject: js)
            let categories = try JSONDecoder().decode([Category].self, from: data)
            
            // Update Cache
            self.categoryCache[type] = categories
            
            return categories
        }
        return []
    }
    
    // MARK: - Search Indexer
    
    @Published public var isIndexing = false
    
    // Background Indexer
    public func buildSearchIndex(force: Bool = false) {
        // RE-ENTRANCY GUARD: Strictly prevent multiple concurrent indexers
        // This check happens on the caller's thread (usually MainActor if from UI) or any thread
        // We rely on the atomic boolean if practical, or MainActor confinement if possible.
        // Given current usage, let's check the property directly.
        if isIndexing {
            print("Indexer: Skiping request (Already Running).")
            return
        }
        
        // 1. Check if we have a valid index on disk
        // FIX: Only skip if we ACTUALLY have items. If the cache is empty (0 items), 
        // a "fresh" timestamp is meaningless (it means the last index failed).
        let currentCount = self.movieCache.count
        
        // CHECK COMPLETION FLAG
        let lastRunSuccess = UserDefaults.standard.bool(forKey: "index_completed_successfully")
        
        if !force, let date = lastIndexDate, currentCount > 0, lastRunSuccess {
             // If index is less than 24 hours old, skip
             if Date().timeIntervalSince(date) < (24 * 3600) {
                 print("Indexer: Skipped. Last index was \(Int(Date().timeIntervalSince(date)/3600)) hours ago (< 24h). Use 'Refresh' in settings to force.")
                 return
             }
        } else {
             if !lastRunSuccess && lastIndexDate != nil {
                 print("Indexer: Partial Cache Detected (Last run failed). Forcing Re-index.")
             }
        }
        
        // 2. Start Background Task - ATOMICALLY SET FLAG AND LAUNCH
        Task { @MainActor in 
            self.isIndexing = true
            
            // Launch the heavy lifting from here to ensure flag is set first
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
            
            print("Starting Background Search Index (Cache Warming)...")
            // WAIT FOR AUTHENTICATION
            // The indexer might be triggered before the initial handshake completes.
            // We wait up to 20 seconds for a valid token.
            var authWaitAttempts = 0
            while self.token == nil && authWaitAttempts < 200 {
                if authWaitAttempts % 20 == 0 {
                    print("Indexer: Waiting for Authentication... (\(authWaitAttempts)/200)")
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                authWaitAttempts += 1
            }
            
            if self.token == nil {
                print("Indexer: Authentication timed out. Aborting index.")
                await MainActor.run { self.isIndexing = false }
                return
            }

            await self.ensureCacheLoaded()
            
            // Frequency Check: 1 Day
            let isCacheEmpty = await MainActor.run { self.movieCache.isEmpty }
            
            if !force && !isCacheEmpty {
                // let lastVersion = UserDefaults.standard.integer(forKey: "index_version") // Unused
                // let currentVersion = 5 // Unused
                
                if let lastDate = UserDefaults.standard.object(forKey: "last_index_date") as? Date { 
                    let hours = Calendar.current.dateComponents([.hour], from: lastDate, to: Date()).hour ?? 0
                    print("Indexer: Check. Last Date: \(lastDate), Now: \(Date()), Hours Diff: \(hours)")
                    
                    // CHECK COMPLETION FLAG (Internal)
                    let lastRunSuccess = UserDefaults.standard.bool(forKey: "index_completed_successfully")
                    
                    if hours < 24 && lastRunSuccess {
                        print("Indexer: Skipped. Last index was \(hours) hours ago (< 24h) and Success=True. Use 'Refresh' in settings to force.")
                        await MainActor.run { self.isIndexing = false }
                        return
                    } else if !lastRunSuccess {
                        print("Indexer: Partial Cache Detected (Internal Check). Forcing Re-index.")
                    }
                } else {
                    print("Indexer: No Last Date found. Treating as Fresh Start.")
                }
            }
            
            // RESET FLAGS ONLY ONCE WE ARE COMMITTED TO RUNNING
            UserDefaults.standard.set(false, forKey: "index_completed_successfully")
            
            let totalStart = Date()
            
            // COMBINE DEFAULT + USER SELECTED CATEGORIES
            let defaults = StalkerClient.defaultIndexedCategoryIDs
            let userSelected = PreferenceManager.shared.additionalIndexedCategoryIds
            let targetIDs = defaults.union(userSelected).filter { $0 != "*" }
             
            print("Indexer: Target Categories: \(targetIDs) (Defaults: \(defaults.count), Custom: \(userSelected.count))")
            
            // Serial Category Fetching (Safe Mode), but Pages are Parallel
            for catId in targetIDs {
                let isPreviouslyCompleted = self.completedCategories.contains(catId)
                
                // RESET status before starting. If we fail, it stays incomplete.
                self.markCategoryIncomplete(catId)
                
                do {
                    _ = try await self.fetchAllPagesForIndexer(categoryId: catId, isPreviouslyCompleted: isPreviouslyCompleted)
                    
                    // MARK SUCCESS for this category
                    self.markCategoryComplete(catId)
                } catch {
                    print("Indexer: CRITICAL FAILURE for Cat \(catId): \(error). Aborting Index.")
                    // STOP EVERYTHING. Do NOT set global success flag.
                    // We still save whatever partial progress we made, but next run will force full scan for failed categories.
                    
                    await MainActor.run { self.isIndexing = false }
                    return
                }
            }

            let duration = Date().timeIntervalSince(totalStart)
            print("Indexer: Complete in \(String(format: "%.1f", duration))s. Cache size: \(self.movieCache.count) items. Saving to Disk...")
            self.saveCacheToDisk()
            
            UserDefaults.standard.set(Date(), forKey: "last_index_date")
            UserDefaults.standard.set(5, forKey: "index_version")
            
            await MainActor.run {
                self.isIndexing = false
                self.logCacheSummary()
                
                // MARK SUCCESS (Only if we got here without throwing)
                UserDefaults.standard.set(true, forKey: "index_completed_successfully")
                UserDefaults.standard.set(duration, forKey: "last_index_duration")
                self.objectWillChange.send()
                print("Indexer: Mark Success Flag = TRUE")
            }
        }
        }
    }


    // Helper to merge movies (extracted to avoid code duplication in parallel loop)
    private func mergeMoviesIntoCache(_ newMovies: [Movie]) async {
        guard !newMovies.isEmpty else { return }
        await MainActor.run {
            var currentCache = self.movieCache
            for var movie in newMovies {
                if let existing = currentCache[movie.id] {
                    // PRESERVE METADATA
                    if (movie.description == nil || movie.description?.isEmpty == true) { movie.description = existing.description }
                    if movie.actors == nil { movie.actors = existing.actors }
                    if movie.director == nil { movie.director = existing.director }
                    if movie.poster == nil && existing.poster != nil { movie.poster = existing.poster }
                    if movie.genresStr == nil { movie.genresStr = existing.genresStr }
                    if movie.duration == nil { movie.duration = existing.duration }
                    
                    // MERGE CATEGORY IDs
                    var currentCats = existing.categoryId?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
                    if let newCat = movie.categoryId {
                        if !currentCats.contains(newCat) {
                             currentCats.append(newCat)
                        }
                    }
                    movie.categoryId = currentCats.joined(separator: ",")
                }
                
                // Update Category Map for O(1) lookup
                if let cats = movie.categoryId?.components(separatedBy: ",") {
                    for cat in cats {
                        let trimmed = cat.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            self.categoryMap[trimmed, default: []].insert(movie.id)
                        }
                    }
                }
                
                currentCache[movie.id] = movie
            }
            self.movieCache = currentCache
            self.cacheCount = currentCache.count
        }
    }
    
    // Updated getMovies to accept start page
    public func getMovies(categoryId: String, startPage: Int = 0, pageLimit: Int = 20, isInteractive: Bool = true, checkCache: Bool = false, skipCacheUpdates: Bool = false) async throws -> [Movie] {
        if isDemoMode {
             // Return Mock Movies (only for movie category)
             if categoryId == "mock_movie_cat" {
                 return await MainActor.run { DemoData.mockMovies }
             } else if categoryId == "mock_series_cat" {
                 return await MainActor.run { DemoData.mockSeries }
             }
             return []
        }

        var allMovies: [Movie] = []
        var page = startPage
        let endPage = startPage + pageLimit - 1
        var hasMore = true
        
        while hasMore && page <= endPage {
            // OPTIMIZATION: Yield to UI Thread (100ms) only for background tasks (if interactive)
            if !isInteractive {
                 try? await Task.sleep(nanoseconds: 10_000_000) // 10ms micro-sleep to prevent total thread hogging
            }
            
            // Try requesting 14 items per page to reduce requests (Optimization)
            let json = try await fetch(action: "get_ordered_list", type: "vod", params: [
                "category": categoryId,
                "p": String(page),
                "sortby": "added",
                "per_page": "14"
            ])
            
            if let root = json as? [String: Any],
               let js = root["js"] as? [String: Any],
               let dataList = js["data"] as? [[String: Any]] {
                
                // Cache Total Items if present
                if !skipCacheUpdates {
                    if let totalStr = js["total_items"] as? String, let t = Int(totalStr) {
                        await MainActor.run { self.categoryMetadata[categoryId] = t }
                    } else if let t = js["total_items"] as? Int {
                        await MainActor.run { self.categoryMetadata[categoryId] = t }
                    }
                }

                // If empty, we reached the end
                if dataList.isEmpty {
                    hasMore = false
                    break
                }
                
                do {
                    // PERFORMANCE FIX: Offload Heavy Decoding to Background Thread
                    // This prevents UI stuttering during parallel fetching
                    // PERFORMANCE FIX: Decoding directly in async context (no detached task) to avoid isolation issues
                    let data = try JSONSerialization.data(withJSONObject: dataList)
                    var movies = try JSONDecoder().decode([Movie].self, from: data)
                    
                    // CRITICAL: Ensure categoryId is set (thread-safe local mod)
                    for i in 0..<movies.count {
                        if movies[i].categoryId == nil {
                            movies[i].categoryId = categoryId
                        }
                    }
                    
                    allMovies.append(contentsOf: movies)

                    // CACHE POPULATION: UI fetches should hydrate the cache for the Indexer
                    if !skipCacheUpdates {
                        await self.mergeMoviesIntoCache(movies)
                    }
                    
                    // SMART SYNC OPTIMIZATION
                    if checkCache {
                        let newIds = movies.map { $0.id }
                        let allExist = await MainActor.run {
                            return newIds.allSatisfy { self.movieCache[$0] != nil }
                        }
                        
                        if allExist {
                            print("Indexer: Cat \(categoryId) Page \(page) already fully cached. Stopping (Smart Sync).")
                            hasMore = false
                            break
                        }
                    }
                } catch {
                    print("Error decoding page \(page) for cat \(categoryId): \(error)")
                }
                
                page += 1
            } else {
                print("Indexer: Stopping at Page \(page) - Invalid JSON structure or Error.")
                hasMore = false
            }
        }
        return allMovies
    }


    
    // MARK: - Disk Persistence
    // Default Indexed Categories (Main ones)
    public static let defaultIndexedCategoryIDs: Set<String> = ["5", "6", "63", "1", "75", "2", "3", "82", "8", "65", "12", "77", "13", "15", "45"]
    
    // Config
    private let maxCacheAgeSeconds: TimeInterval = 24 * 3600 // 1 Day
    
    private var cacheFileURL: URL? {
        // Use .cachesDirectory which is guaranteed to be writable and appropriate for index/cache data
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        
        let appCacheDir = cachesDir.appendingPathComponent("IPTVLink_Cache", isDirectory: true)
        return appCacheDir.appendingPathComponent("search_index.json")
    }
    
    // Helper for Indexer
    public func fetchAllPagesForIndexer(categoryId: String, isPreviouslyCompleted: Bool) async throws -> [Movie] {
        var allMovies: [Movie] = []
        
        // Step 1: Fetch Page 0 to get total count
        do {
            let (firstPageMovies, totalItems) = try await getMoviesWithCount(categoryId: categoryId, page: 0)
            allMovies.append(contentsOf: firstPageMovies)
            await self.mergeMoviesIntoCache(firstPageMovies) // SAVE PAGE 0 IMMEDIATELY
            
            if totalItems == 0 || firstPageMovies.isEmpty { return allMovies }
            
            // Calculate remaining pages (per_page = 14)
            let perPage = 14 
            let totalPages = Int(ceil(Double(totalItems) / Double(perPage)))
            
            if totalPages <= 1 { return allMovies }
            
            print("Indexer: Cat \(categoryId) has \(totalItems) items (\(totalPages) pages). Fetching with 1-page parallelism (Serial)... Status: \(isPreviouslyCompleted ? "Completed Previously" : "Partial/New")")
            
            // Step 2: Serial Fetch (Limit 1 Page) to prevent Network Saturation
            try await withThrowingTaskGroup(of: [Movie].self) { group in
                var activeTasks = 0
                let maxConcurrency = 1 // SERIAL execution
                var shouldStop = false
                var consecutiveMatchedPages = 0
                
                for p in 1..<totalPages {
                    if shouldStop { break }
                    
                    // Backoff: Check for recent user activity
                    if Date().timeIntervalSince(self.lastUIInteraction) < 5 { // 5 Seconds window
                        print("Indexer: Yielding to UI (User Active)... Pausing 10s.")
                        try? await Task.sleep(nanoseconds: 10_000_000_000) // Sleep 10s
                    }
                    
                    // Throttle: 200ms delay to yield to UI/Player and prevent Protocol 42
                    try? await Task.sleep(nanoseconds: 200_000_000)

                    if activeTasks >= maxConcurrency {
                        if let result = try await group.next() {
                            let firstId = result.first?.id ?? "nil"
                            
                            // Check for Server Loop / Duplicate Page
                            var isServerDuplicate = false
                            if let first = result.first, allMovies.contains(where: { $0.id == first.id }) {
                                 print("Indexer: Server returned Duplicate Page for Cat \(categoryId) (Start ID: \(firstId)). Skipping this batch.")
                                 isServerDuplicate = true
                            }
                            
                            var wasFullyCached = false
                            
                            // Only run Smart Sync check if it's NOT a server duplicate
                            if !isServerDuplicate && !result.isEmpty {
                                let newIds = result.map { $0.id }
                                let targetCat = categoryId
                                let allExistAndLinked = await MainActor.run {
                                    return newIds.allSatisfy { id in
                                        if let existing = self.movieCache[id] {
                                            let cats = existing.categoryId?.components(separatedBy: ",") ?? []
                                            return cats.contains(targetCat)
                                        }
                                        return false
                                    }
                                }
                                
                                if allExistAndLinked {
                                    consecutiveMatchedPages += 1
                                    
                                    // OPTIMIZATION: Only stop early if we have a success record for this cat AND 2 consecutive matches.
                                    // This prevents "holes" from previous partial crashes.
                                    if isPreviouslyCompleted && consecutiveMatchedPages >= 2 {
                                        wasFullyCached = true
                                        print("Indexer: Smart Sync - Cat \(categoryId) matches 2 consecutive pages. Stopping early.")
                                    } else if isPreviouslyCompleted {
                                        print("Indexer: Smart Sync - Cat \(categoryId) Page is fully cached. Need 1 more.")
                                    }
                                } else {
                                    // Reset counter if we find a missing item
                                    consecutiveMatchedPages = 0
                                }
                            }
                            
                            if !isServerDuplicate {
                                allMovies.append(contentsOf: result)
                                await self.mergeMoviesIntoCache(result) // INCREMENTAL SAVE
                                
                                if wasFullyCached {
                                    shouldStop = true
                                }
                            }
                            
                            activeTasks -= 1
                        }
                    }
                    
                    if shouldStop { break }
                    
                    group.addTask {
                        do {
                            return try await self.getMovies(categoryId: categoryId, startPage: p, pageLimit: 1, skipCacheUpdates: true)
                        } catch {
                            print("Indexer: Failed page \(p) for cat \(categoryId): \(error)")
                            throw error
                        }
                    }
                    activeTasks += 1
                }
                
                // Collect remaining
                for try await result in group {
                    allMovies.append(contentsOf: result)
                    await self.mergeMoviesIntoCache(result) 
                }
            }
            
        } catch {
            print("Indexer: Failed to init fetch for cat \(categoryId): \(error)")
            throw error
        }
        
        return allMovies
    }
    
    // Helper to get total count (Private)
    private func getMoviesWithCount(categoryId: String, page: Int) async throws -> ([Movie], Int) {
         let json = try await fetch(action: "get_ordered_list", type: "vod", params: [
             "category": categoryId,
             "p": String(page),
             "sortby": "added",
             "per_page": "14" // Safe
         ])
         
         var movies: [Movie] = []
         var total = 0
         
         if let root = json as? [String: Any],
            let js = root["js"] as? [String: Any] {
             
             if let totalStr = js["total_items"] as? String, let t = Int(totalStr) {
                 total = t
             } else if let t = js["total_items"] as? Int {
                 total = t
             }
             
             // Update Metadata Cache
             let finalTotal = total
             await MainActor.run { self.categoryMetadata[categoryId] = finalTotal }
             
             if let dataList = js["data"] as? [[String: Any]] {
                 let data = try JSONSerialization.data(withJSONObject: dataList)
                 movies = try JSONDecoder().decode([Movie].self, from: data)
                 
                 // Critical: Inject Category ID so checking cache actually works
                 for i in 0..<movies.count {
                     movies[i].categoryId = categoryId
                 }
             }
         }
         return (movies, total)
    }

    private func saveCacheToDisk() {
        guard let url = cacheFileURL else { return }
        Task(priority: .background) {
            do {
                // Ensure directory exists (Critical for Apple TV/Sandboxed environments)
                let directory = url.deletingLastPathComponent()
                
                // Create withIntermediateDirectories: true will create 'Application Support' AND our subdir if missing
                if !FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                }
                
                // Convert [String: Movie] -> [Movie] array for smaller JSON (assuming ID is in Movie)
                // Actually cache is Dict, let's just save the Dict values array to be standard
                let items = Array(self.movieCache.values)
                let data = try JSONEncoder().encode(items)
                try data.write(to: url)
                print("Indexer: Saved \(items.count) items to \(url.path)")
                
                // Update Timestamp on Main Actor
                await MainActor.run {
                    self.lastIndexDate = Date()
                    self.calculateCacheSize()
                    
                    // MARK SUCCESS
                    UserDefaults.standard.set(true, forKey: "index_completed_successfully")
                    print("Indexer: Mark Success Flag = TRUE")
                }
            } catch {
                print("Indexer: Save failed: \(error)")
            }
        }
    }
    
    private func loadCacheFromDisk() async {
        guard let url = cacheFileURL else { return }
        
        // PERFORMANCE FIX: Decoding directly in async context to avoid isolation issues
        // The file read and decode will happen on the background thread of the Task calling this.
        var movies: [String: Movie]? = nil
        var count = 0
        
        if let data = try? Data(contentsOf: url),
           let items = try? JSONDecoder().decode([Movie].self, from: data) {
            var cache: [String: Movie] = [:]
            var corruptCount = 0
            
            for item in items {
                // CORRUPT CACHE CHECK: If categoryId is missing, this cache is useless for hybrid fetch
                if item.categoryId == nil {
                    corruptCount += 1
                }
                cache[item.id] = item
            }
            
            // If significant corruption found (e.g., > 10% or > 100 items), discard
            if corruptCount > 100 {
                print("Indexer: DETECTED CORRUPT CACHE (\(corruptCount) items missing CategoryID). Nuking cache to force rebuild.")
                movies = nil
                count = 0
                // Signal Force Re-index
                Task { [weak self] in self?.buildSearchIndex(force: true) }
            } else {
                movies = cache
                count = items.count
            }
        }
        
        if let movies = movies {
            // Calculate Metadata Counts from Cache
            var counts: [String: Int] = [:]
            for movie in movies.values {
                if let catId = movie.categoryId {
                     let cats = catId.components(separatedBy: ",")
                     for c in cats {
                         let trimmed = c.trimmingCharacters(in: .whitespaces)
                         if !trimmed.isEmpty {
                            counts[trimmed, default: 0] += 1
                         }
                     }
                }
            }
            
            let finalMovies = movies
            let finalCounts = counts
            let finalCount = count
            
            await MainActor.run {
                self.movieCache = finalMovies
                self.cacheCount = finalMovies.count
                self.categoryMap = [:] // Rebuild
                for movie in finalMovies.values {
                    if let catId = movie.categoryId {
                        let cats = catId.components(separatedBy: ",")
                        for c in cats {
                            let trimmed = c.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                self.categoryMap[trimmed, default: []].insert(movie.id)
                            }
                        }
                    }
                }
                self.categoryMetadata = finalCounts
                self.calculateCacheSize()
                print("Indexer: Loaded \(finalCount) items and rebuilt Category Map.")
            }
        } else {
            // If load failed or was nuked, ensure we have empty state
             await MainActor.run {
                self.movieCache = [:]
                self.cacheCount = 0
            }
        }
    }
    

    
    // MARK: - Local Cache Access
    public func getCachedMovies(categoryId: String) -> [Movie] {
        // PERFORMANCE FIX: Use O(1) Category Map instead of filtering all movies
        let movieIds = categoryMap[categoryId] ?? []
        let movies = movieIds.compactMap { movieCache[$0] }
        
        // Sort by Added Date Descending
        return movies.sorted {
            let date1 = $0.added ?? ""
            let date2 = $1.added ?? ""
            if date1 == date2 {
                 return $0.id > $1.id
            }
            return date1 > date2
        }
    }
    
    // Category Completion Flags for Smart Sync
    private var completedCategories: Set<String> {
        get {
            let list = UserDefaults.standard.stringArray(forKey: "indexed_categories") ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "indexed_categories")
        }
    }
    
    private func markCategoryComplete(_ id: String) {
        var current = self.completedCategories
        current.insert(id)
        self.completedCategories = current
    }
    
    private func markCategoryIncomplete(_ id: String) {
        var current = self.completedCategories
        current.remove(id)
        self.completedCategories = current
    }
    
    // Auth Session
    // Updated getMovies to accept start page
    public func getSeriesSeasons(seriesId: String) async throws -> [Movie] {
        // Fetch Seasons: passing season_id = 0 returns the list of seasons
        let json = try await fetch(action: "get_ordered_list", type: "vod", params: [
            "movie_id": seriesId,
            "season_id": "0",
            "episode_id": "0",
            "p": "1",
            "per_page": "50" // Increase limit to fetch all seasons at once
        ])
        
        print("DEBUG: getSeriesSeasons (movie_id=\(seriesId)) RAW: \(json)")
        
        if let root = json as? [String: Any],
           let js = root["js"] as? [String: Any],
           let dataList = js["data"] as? [[String: Any]] {
            
            if dataList.isEmpty {
                 print("DEBUG: getSeriesSeasons EMPTY for series \(seriesId)")
            }
            
            let data = try JSONSerialization.data(withJSONObject: dataList)
            let seasons = try JSONDecoder().decode([Movie].self, from: data)
            return seasons
        }
        
        return []
    }
    
    public func getSeasonEpisodes(seriesId: String, seasonId: String) async throws -> [Movie] {
        var allEpisodes: [Movie] = []
        var page = 1
        var hasMore = true
        
        // Seasons rarely have more than a few pages of episodes, but keeping logic
        let perPage = 50
        
        while hasMore && page <= 10 {
            let json = try await fetch(action: "get_ordered_list", type: "vod", params: [
                "movie_id": seriesId,
                "season_id": seasonId,
                "episode_id": "0",
                "p": String(page),
                "per_page": String(perPage)
            ])
            
            if let root = json as? [String: Any],
               let js = root["js"] as? [String: Any],
               let dataList = js["data"] as? [[String: Any]] {
                
                if dataList.isEmpty {
                    hasMore = false
                    break
                }
                
                // STOP FETCHING if we got fewer items than the page limit (End of List)
                if dataList.count < perPage {
                    hasMore = false
                }
                
                do {
                    let data = try JSONSerialization.data(withJSONObject: dataList)
                    var episodes = try JSONDecoder().decode([Movie].self, from: data)
                    
                    // Inject IDs
                    for i in 0..<episodes.count {
                        episodes[i].seriesId = seriesId
                        episodes[i].seasonId = seasonId
                    }
                    allEpisodes.append(contentsOf: episodes)
                } catch {
                     print("Error decoding episodes page \(page): \(error)")
                }
                page += 1
            } else {
                hasMore = false
            }
        }
        
        return allEpisodes
    }
    
    public func getEpisodeFiles(seriesId: String, seasonId: String, episodeId: String) async throws -> [Movie] {
        // Fetch specific files for an episode (e.g., qualities, languages)
        // This appears to be the only way to get the 'cmd' for Series episodes
        let json = try await fetch(action: "get_ordered_list", type: "vod", params: [
            "movie_id": seriesId,
            "season_id": seasonId,
            "episode_id": episodeId,
            "p": "1",
            "not_ended": "0" // Found in trace
        ])
        
        print("DEBUG: getEpisodeFiles (epId=\(episodeId)) RAW: \(json)")
        
        if let root = json as? [String: Any],
           let js = root["js"] as? [String: Any],
           let dataList = js["data"] as? [[String: Any]] {
            
            let data = try JSONSerialization.data(withJSONObject: dataList)
            // These items are technically "Movies" in structure (have cmd, name, etc)
            let files = try JSONDecoder().decode([Movie].self, from: data)
            return files
        }
        
        return []
    }
    
    // MARK: - Search API
    
    public func searchMovies(query: String) async throws -> [Movie] {
        // 1. API Search (Server usually searches Name only)
        // Adding wildcards can help on some Stalker versions
        // We use Task group to perform local vs remote if needed, but simple await is fine for now.
        
        var apiResults: [Movie] = []
        
        // Attempt API Fetch
        // We wrap in do-catch so API failure doesn't block local cache results? 
        // Or strictly fail? Let's try to be robust.
        // Limit API results to prevent massive payloads
        do {
            let json = try await fetch(action: "get_ordered_list", type: "vod", params: [
                "search": query,
                "sort_by": "added",
                "per_page": "50" // SAFEGUARD: Limit server response size
            ])
            
            if let root = json as? [String: Any],
               let js = root["js"] as? [String: Any],
               let dataList = js["data"] as? [[String: Any]] {
                let data = try JSONSerialization.data(withJSONObject: dataList)
                apiResults = try JSONDecoder().decode([Movie].self, from: data)
            }
        } catch {
            print("API Search failed: \(error) - Falling back to Local Cache only.")
        }
        
        print("DEBUG: Search Query: '\(query)' | API Results: \(apiResults.count) | Local Cache Size: \(self.movieCache.count)")
        
        // Debug: Inspect specific movie if in cache
        if let movie = self.movieCache.values.first(where: { $0.name.contains("Voyeurs") }) {
             print("DEBUG: Found 'The Voyeurs' in Local Cache. Actors: '\(movie.actors ?? "nil")'")
        } else {
             print("DEBUG: 'The Voyeurs' NOT found in Local Cache.")
        }
        
        // 2. Local Cache Search (Search Actors, Directors, Names in loaded content)
        // This is critical because Stalker APIs often IGNORE actors in search.
        // SAFEGUARD: Limit local search scan if cache is huge (though filter is fast, result set matters)
        let localResults = self.movieCache.values.filter { movie in
            if movie.name.localizedCaseInsensitiveContains(query) { return true }
            if let actors = movie.actors, actors.localizedCaseInsensitiveContains(query) {
                 // print("DEBUG: match found in actors for \(movie.name)")
                 return true
            }
            if let director = movie.director, director.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
        
        print("DEBUG: Local Matches found: \(localResults.count)")
        
        // 3. Merge & Deduplicate
        // Priority: API results first (usually fresher?), then Local
        // Use Set for ID tracking
        var ids = Set(apiResults.map { $0.id })
        var finalResults = apiResults
        
        for movie in localResults {
            if !ids.contains(movie.id) {
                finalResults.append(movie)
                ids.insert(movie.id)
            }
        }
        
        // SAFEGUARD: Cap total results to 100 to prevent UI issues
        if finalResults.count > 100 {
            return Array(finalResults.prefix(100))
        }
        return finalResults
    }
    
    public func searchChannels(query: String) async throws -> [Channel] {
        // Stalker Action: get_ordered_list with type 'itv' and search param
        let json = try await fetch(action: "get_ordered_list", type: "itv", params: [
            "search": query,
            "sort_by": "name",
            "per_page": "50" // SAFEGUARD
        ])
        
        print("DEBUG: searchChannels query=\(query) RAW: \(json)")
        
        if let root = json as? [String: Any],
           let js = root["js"] as? [String: Any],
           let dataList = js["data"] as? [[String: Any]] {
            
            let data = try JSONSerialization.data(withJSONObject: dataList)
            return try JSONDecoder().decode([Channel].self, from: data)
        }
        return []
    }
    
       public func getChannels(categoryId: String, startPage: Int = 1, pageLimit: Int = 20) async throws -> [Channel] {
        if isDemoMode {
            return await MainActor.run { DemoData.mockChannels }
        }
        
        var allChannels: [Channel] = []
        var page = startPage
        let endPage = startPage + pageLimit - 1
        var hasMore = true
        
        while hasMore && page <= endPage {
            let json = try await fetch(action: "get_ordered_list", type: "itv", params: [
                "genre": categoryId,
                "sort_by": "number",
                "p": String(page)
            ])
            
            if let root = json as? [String: Any],
               let js = root["js"] as? [String: Any],
               let dataList = js["data"] as? [[String: Any]] {
                
                if dataList.isEmpty {
                    hasMore = false
                    break
                }
                
                do {
                     let data = try JSONSerialization.data(withJSONObject: dataList)
                     let channels = try JSONDecoder().decode([Channel].self, from: data)
                     allChannels.append(contentsOf: channels)
                } catch {
                    print("Error decoding channels page \(page): \(error)")
                }
                page += 1
            } else {
                hasMore = false
            }
        }
        // print("DEBUG: getChannels success. Count: \(allChannels.count)")
        return allChannels
    }
    
    // MARK: - Stream Generation
    
    public func getVodInfo(movieId: String) async throws -> Movie? {
        if isDemoMode {
             // Check Mock Data
             if let movie = await MainActor.run(body: { DemoData.mockMovies.first(where: { $0.id == movieId }) }) { return movie }
             if let series = await MainActor.run(body: { DemoData.mockSeries.first(where: { $0.id == movieId }) }) { return series }
             // Mock Episodes if needed
             if let ep = await MainActor.run(body: { DemoData.mockEpisodes.first(where: { $0.id == movieId }) }) { return ep }
             return nil // Return nil instead of throwing for consistency with optional return
        }

        // Check Mem Cacheck local VOD cache first (MainActor Safety)
        if let cached = await MainActor.run(body: { vodInfoCache[movieId] }) {
            // print("DEBUG: Using cached VOD info for \(movieId)")
            return cached
        }

        // 2. Fetch from Network (Directly in caller's task context)
        // This ensures if the caller (UI) cancels the task, this network request stops immediately.
        do {
            let json = try await fetch(action: "get_vod_info", type: "vod", params: ["movie_id": movieId])
                
            // 3. Offload Parsing to Background Thread
            // We use Task.detached but await it, so we can return the value.
            // We do NOT start a new unstructured top-level Task that ignores cancellation.
            let movie = try await Task.detached(priority: .userInitiated) { () -> Movie? in
                if let root = json as? [String: Any],
                   let js = root["js"] as? [String: Any] {
                    
                    if let data = js["data"] as? [String: Any] {
                        return try? self.parseMovieFrom(data)
                    } else if let dataList = js["data"] as? [[String: Any]],
                              let first = dataList.first {
                        return try? self.parseMovieFrom(first)
                    }
                }
                return nil
            }.value
            
            // 4. Update Caches (Main Actor)
            if var movie = movie {
                // LOOP FIX: If description is still missing even after detail fetch (Server data issue),
                // we set it to a placeholder. This ensures the UI doesn't try to fetch again endlessly.
                if movie.description == nil || movie.description?.isEmpty == true {
                    movie.description = " " // Single space marks it as "Checked" for UI logic
                }
                
                await MainActor.run {
                    self.vodInfoCache[movieId] = movie
                    
                    // Also update main list cache if present, to populate details
                    // Note: movieCache might contain partial info, we overwrite with full info
                    // But we should verify we aren't losing anything (usually detail > list)
                    self.movieCache[movieId] = movie
                }
                return movie
            }
            return nil
        } catch is CancellationError {
            // BENIGN: Task cancelled (user scrolled away). Do not log as error.
            return nil
        } catch {
             // Check for NSURLErrorCancelled as well
             let nsError = error as NSError
             if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                 return nil
             }
             
             // Log actual errors
             print("getVodInfo Failed: \(error)")
             throw error
        }
    }
    
    private func parseMovieFrom(_ data: [String: Any]) throws -> Movie {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(Movie.self, from: jsonData)
    }

    public func createLink(type: String, cmd: String) async throws -> String {
        // Stalker Action: create_link
        // cmd often comes as "ffrt http://..." or "auto http://...". We pass it as is usually.
        
        // DEMO MODE: Return direct URL
        if isDemoMode {
            return cmd
        }

        // 1. Check if cmd is already a http link (Local/Raw)
        if cmd.hasPrefix("http") { return cmd }
        
        let json = try await fetch(action: "create_link", type: type, params: [
            "cmd": cmd,
            "forced_storage": "0",
            "disable_ad": "0",
            "js_authenticate": "1"
        ])
        
        // Parse: { "js": { "cmd": "http://stream..." } }
        if let root = json as? [String: Any],
           let js = root["js"] as? [String: Any],
           var streamURL = js["cmd"] as? String {
            
            print("DEBUG: create_link RAW response: \(streamURL)")
            
            // Stalker sometimes returns "ffmpeg http://..." or "auto http://..." or multiple URLs separated by space
            // We usually want the actual URL part.
            
            // 1. Split by spaces and find the component starting with http/rtsp
            let components = streamURL.components(separatedBy: .whitespaces)
            if let validUrl = components.first(where: { $0.hasPrefix("http") || $0.hasPrefix("rtsp") }) {
                streamURL = validUrl
            }
            
            print("DEBUG: create_link Cleaned URL: \(streamURL)")
            return streamURL
        }
        
        throw StalkerError.decodingError(NSError(domain: "Stalker", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to extract link from create_link response"]))
    }
    
    // MARK: - Image Fetching
    
    // Simple In-Memory Cache
    public let imageCache = NSCache<NSURL, UIImage>()
    public let dataCache = NSCache<NSURL, NSData>()
    
    // Deduplication for in-flight image requests
    private var inFlightImageTasks: [NSURL: Task<UIImage?, Error>] = [:]
    private var inFlightDataTasks: [NSURL: Task<Data, Error>] = [:]
    private let imageTaskLock = NSLock()
    
    // Performance: Category Mapping for O(1) lookup
    // Map of CategoryID -> Set of MovieIDs
    private var categoryMap: [String: Set<String>] = [:]
    
    // Limit to 20 concurrent requests for Images (Faster, smaller)
    private let imageSemaphore = AsyncSemaphore(value: 20)
    
    // Limit to 4 concurrent DECODES to prevent CPU spikes / Main thread lag
    private let decodeSemaphore = AsyncSemaphore(value: 4)

    public func fetchImage(url: URL, targetSize: CGSize? = nil) async throws -> UIImage? {
        // 1. Construct Cache Key (Include size if downsampling)
        let cacheKey: NSURL
        if let size = targetSize {
            cacheKey = NSURL(string: url.absoluteString + "_\(Int(size.width))x\(Int(size.height))")!
        } else {
            cacheKey = url as NSURL
        }
        
        // 2. Check UIImage Cache (Size-specific)
        if let cached = imageCache.object(forKey: cacheKey) {
            print("DEBUG: 📦 CACHE HIT: \(url.lastPathComponent)")
            return cached
        }
        
        // 3. Deduplicate In-Flight Image Tasks (Fetch + Decode)
        imageTaskLock.lock()
        if let existingTask = inFlightImageTasks[cacheKey] {
            imageTaskLock.unlock()
            print("DEBUG: 🤝 JOINING IN-FLIGHT IMAGE: \(url.lastPathComponent)")
            return try await existingTask.value
        }
        
        let imageTask = Task<UIImage?, Error> {
            // Check Data Cache (Raw bytes) to skip network if any size of this image exists
            let dataKey = url as NSURL
            var data: Data? = dataCache.object(forKey: dataKey) as Data?
            
            if let d = data {
                print("DEBUG: 📦 DATA CACHE HIT: \(url.lastPathComponent)")
            } else {
                // Deduplicate Data Task (Network only)
                imageTaskLock.lock()
                let dataTask: Task<Data, Error>
                if let existingDataTask = inFlightDataTasks[dataKey] {
                    dataTask = existingDataTask
                    imageTaskLock.unlock()
                    print("DEBUG: 🤝 JOINING IN-FLIGHT DATA: \(url.lastPathComponent)")
                } else {
                    let newTask = Task<Data, Error> {
                        defer { 
                            imageTaskLock.lock()
                            inFlightDataTasks.removeValue(forKey: dataKey)
                            imageTaskLock.unlock()
                        }
                        
                        await imageSemaphore.wait()
                        defer { Task { await imageSemaphore.signal() } }
                        
                        try Task.checkCancellation()
                        
                        let request = URLRequest(url: url)
                        print("DEBUG: 🚀 NETWORK START: \(url.lastPathComponent)")
                        let (d, _) = try await session.data(for: request)
                        
                        // Store raw bytes in Data Cache
                        self.dataCache.setObject(d as NSData, forKey: dataKey)
                        
                        return d
                    }
                    inFlightDataTasks[dataKey] = newTask
                    dataTask = newTask
                    imageTaskLock.unlock()
                }
                data = try await dataTask.value
            }
            
            guard let finalData = data, !finalData.isEmpty else { return nil }
            
            // 4. Decode & Cache (OFF MAIN THREAD)
            return await Task.detached(priority: .userInitiated) { () -> UIImage? in
                // CPU PROTECTION: Limit concurrent decodes
                await self.decodeSemaphore.wait()
                defer { Task { await self.decodeSemaphore.signal() } }
                
                if let size = targetSize {
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height)
                    ]
                    
                    if let source = CGImageSourceCreateWithData(finalData as CFData, nil) {
                        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                             let mb = Double(finalData.count)/1024.0/1024.0
                             print("DEBUG: ✅ DECODE SUCCESS [\(String(format: "%.2f", mb)) MB] -> \(cgImage.width)x\(cgImage.height) | \(url.lastPathComponent)")
                             return UIImage(cgImage: cgImage)
                        } else {
                            print("DEBUG: ⚠️ DOWNSAMPLE FAILED for \(url.lastPathComponent). Falling back to full decode.")
                        }
                    }
                } 
                
                if let image = UIImage(data: finalData) {
                     print("DEBUG: ✅ FULL DECODE SUCCESS [\(String(format: "%.2f", Double(finalData.count)/1024.0/1024.0)) MB] | \(url.lastPathComponent)")
                     return image
                }
                
                print("DEBUG: ❌ DECODE FAILED for \(url.lastPathComponent).")
                return nil
            }.value
        }
        
        inFlightImageTasks[cacheKey] = imageTask
        imageTaskLock.unlock()
        
        do {
            let result = try await imageTask.value
            if let img = result {
                imageCache.setObject(img, forKey: cacheKey)
            }
            
            imageTaskLock.lock()
            inFlightImageTasks.removeValue(forKey: cacheKey)
            imageTaskLock.unlock()
            
            return result
        } catch {
            imageTaskLock.lock()
            inFlightImageTasks.removeValue(forKey: cacheKey)
            imageTaskLock.unlock()
            throw error
        }
    }

    public func fetchImageData(url: URL) async throws -> Data {
        let request = URLRequest(url: url)
        // Session already has User-Agent, Cookies, etc.
        let (data, _) = try await session.data(for: request)
        return data
    }
    
    // MARK: - Helper
    public func resolveRedirect(url: URL) async -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, let finalURL = httpResponse.url {
                 print("DEBUG: Resolved Redirect: \(url) -> \(finalURL)")
                 return finalURL
            }
        } catch {
             print("DEBUG: Failed to resolve redirect: \(error). Using original URL.")
        }
        return url
    }
    private func logCacheSummary() {
        Task(priority: .background) {
            print("--------------------------------------------------")
            print("Indexer: Generating Cache Summary (Total: \(self.movieCache.count))...")
            var counts: [String: Int] = [:]
            
            for movie in self.movieCache.values {
                if let cats = movie.categoryId?.split(separator: ",") {
                    for c in cats {
                        let cid = String(c)
                        counts[cid, default: 0] += 1
                    }
                } else {
                    counts["unknown", default: 0] += 1
                }
            }
            
            let sortedInfo = counts.sorted { $0.key < $1.key }.map { "Cat \($0.key): \($0.value)" }
            print("Indexer: Cache Distribution:\n\(sortedInfo.joined(separator: ", "))")
            print("--------------------------------------------------")
        }
    }
    
    // MARK: - Hybrid Cache Strategy
    
    public var isCacheStale: Bool {
        guard let lastDate = lastIndexDate else { return true }
        // 24 Hours in seconds
        return Date().timeIntervalSince(lastDate) > (24 * 3600)
    }
    
    // Helper to filter 50k+ items off the main thread to prevent UI freeze
    private func fetchCachedMoviesBackground(categoryId: String) async -> [Movie] {
         // 1. Snapshot values on MainActor (Thread Safety for Dictionary Read)
         let copy = await MainActor.run { return Array(self.movieCache.values) }
         
         // 2. Detached Task for Heavy Filtering
         return await Task.detached(priority: .userInitiated) {
             // Filter
             let filtered = copy.filter { movie in
                 guard let validIds = movie.categoryId else { return false }
                 // Optimization: Avoid split if exact match
                 if validIds == categoryId { return true }
                 
                 let idList = validIds.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                 return idList.contains(categoryId)
             }
             
             // Sort by Added Date Descending
             return filtered.sorted {
                 let date1 = $0.added ?? ""
                 let date2 = $1.added ?? ""
                 if date1 == date2 {
                      return $0.id > $1.id
                 }
                 return date1 > date2
             }
         }.value
    }

    public func getHybridMovies(categoryId: String) async throws -> [Movie] {
        // Mark User Activity
        await MainActor.run { self.lastUIInteraction = Date() }
        
        // DEDUPLICATION: Join existing in-flight request if present
        if let existingTask = hybridFetchTasks[categoryId] {
            print("HybridFetch: Joining in-flight fetch for Cat \(categoryId)")
            return try await existingTask.value
        }
        
        let task = Task<[Movie], Error> {
            await ensureCacheLoaded()
            
            // Scenario 1: Cache is Fresh (< 24 Hours)
        // Just return full cache instantly.
        if !isCacheStale {
            // OFF-THREAD FILTERING
            let cached = await fetchCachedMoviesBackground(categoryId: categoryId)
            if !cached.isEmpty {
                return cached
            }
        }
        
        // Scenario 2: Cache is Stale OR Empty (> 24 Hours)
        // Fetch Top 2 Pages "Live" to ensure freshness
        // Then backfill with whatever is in cache
        
        print("HybridFetch: Cache Stale/Empty for Cat \(categoryId). Fetching Fresh Head...")
        
        // 1. Fetch Fresh
        // We fetch Page 0 and 1 (approx 28 items)
        let freshMovies = try await getMovies(categoryId: categoryId, startPage: 0, pageLimit: 2)
        
        // 2. Get Cache Backfill (OFF-THREAD)
        let cachedMovies = await fetchCachedMoviesBackground(categoryId: categoryId)
        
        // 3. Merge (Deduplicated)
        // Ensure absolutely NO duplicates exist in the final list
        var seenIDs = Set<String>()
        var finalMovies: [Movie] = []
        
        // Add Fresh (Priority)
        for movie in freshMovies {
            // Guard against duplicates within the fresh batch itself
            if !seenIDs.contains(movie.id) {
                seenIDs.insert(movie.id)
                finalMovies.append(movie)
            }
        }
        
        // Add Cached (Backfill)
        for movie in cachedMovies {
            // Guard against duplicates from cache or already present in fresh
            if !seenIDs.contains(movie.id) {
                seenIDs.insert(movie.id)
                finalMovies.append(movie)
            }
        }
        
        // 4. Trigger Background Index Refresh (if not already running)
        if !isIndexing {
            Task {
                // Respect the 24h timer (force: false). 
                // We only want to trigger a background index if the entire index is actually expired.
                self.buildSearchIndex(force: false)
            }
        }
        
        return finalMovies
        }
        
        // Store and await
        hybridFetchTasks[categoryId] = task
        
        do {
            let result = try await task.value
            hybridFetchTasks.removeValue(forKey: categoryId)
            return result
        } catch {
            hybridFetchTasks.removeValue(forKey: categoryId)
            throw error
        }
    }
    // MARK: - Cache Management
    
    public func clearCache() {
        Task(priority: .userInitiated) {
            // 1. Clear Memory
            await MainActor.run {
                self.movieCache.removeAll()
                self.categoryMetadata.removeAll()
                self.vodInfoCache.removeAll()
                self.movies.removeAll()
                self.lastIndexDate = nil
                self.categoryCache.removeAll()
                self.objectWillChange.send()
            }
            
            // 2. Clear Disk
            if let url = self.cacheFileURL {
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                        print("Cache: Removed index file at \(url.path)")
                    }
                } catch {
                    print("Cache: Failed to remove index file: \(error)")
                }
            }
            
            // 3. Clear UserDefaults Metadata
            UserDefaults.standard.removeObject(forKey: "last_index_date") // Fixed Key
            UserDefaults.standard.removeObject(forKey: "index_completed_successfully") // Clear Success Flag
            
            self.calculateCacheSize()
        }
    }
    
    public func calculateCacheSize() {
        guard let url = cacheFileURL else { 
            Task { @MainActor in self.cacheSizeString = "0 KB" }
            return 
        }
        
        Task(priority: .background) {
            var sizeString = "0 KB"
            do {
                let resources = try url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resources.fileSize {
                    let mb = Double(fileSize) / 1024.0 / 1024.0
                    if mb >= 1.0 {
                        sizeString = String(format: "%.1f MB", mb)
                    } else {
                        let kb = Double(fileSize) / 1024.0
                        sizeString = String(format: "%.1f KB", kb)
                    }
                }
            } catch {
                // File doesn't exist or other error
                sizeString = "0 KB"
            }
            
            await MainActor.run {
                self.cacheSizeString = sizeString
            }
        }
    }

}
