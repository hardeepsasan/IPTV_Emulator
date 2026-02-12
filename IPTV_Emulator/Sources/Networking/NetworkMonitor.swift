import Foundation
import Network
import Combine

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected: Bool = true
    @Published var isCellular: Bool = false
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            if !path.isExpensive {
                self.checkInternetAccess(path: path)
            }
        }
        monitor.start(queue: queue)
    }
    
    // Polling Timer for Auto-Recovery
    // If we are "Offline" but the Interface is "Up" (Simulator scenario), NWPathMonitor won't fire when internet returns.
    // We must poll to self-recover.
    private var recoveryTimer: Timer?
    
    private func startRecoveryPolling() {
        guard recoveryTimer == nil else { return }
        print("DEBUG: NetworkMonitor - Starting Recovery Polling...")
        
        DispatchQueue.main.async {
            self.recoveryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                guard !self.isConnected else {
                    self.stopRecoveryPolling()
                    return
                }
                // Check using the current path from monitor is tricky, so we just do a raw ping
                self.performPingCheck(attempt: 1)
            }
        }
    }
    
    private func stopRecoveryPolling() {
        if recoveryTimer != nil {
             print("DEBUG: NetworkMonitor - Stopping Recovery Polling (Back Online)")
             recoveryTimer?.invalidate()
             recoveryTimer = nil
        }
    }
    
    private var currentProbeWorkItem: DispatchWorkItem?

    private func checkInternetAccess(path: NWPath) {
        // Debounce: Cancel pending probe if a new path update comes in quickly
        currentProbeWorkItem?.cancel()
        
        // 1. If System says NO, it's NO.
        if path.status != .satisfied {
            DispatchQueue.main.async {
                self.isConnected = false
                print("DEBUG: NetworkMonitor - Path Unsatisfied (System). isConnected = false")
                self.startRecoveryPolling()
            }
            return
        }
        
        // 2. If System says YES, Schedule Probe
        let workItem = DispatchWorkItem { [weak self] in
            self?.performPingCheck(attempt: 1)
        }
        currentProbeWorkItem = workItem
        // Slight delay to allow DNS to settle on "cold" reconnect
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func performPingCheck(attempt: Int) {
        // Chain: Apple -> Google
        // If both fail, and attempt < 2, wait 1s and retry Chain.
        
        let primaryURL = URL(string: "https://captive.apple.com/hotspot-detect.html")!
        let fallbackURL = URL(string: "https://www.google.com")!
        
        func probe(url: URL, completion: @escaping (Bool) -> Void) {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 3.0 // 3s timeout
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            
            // Use ephemeral session to avoid caching connection state
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 3.0
            config.timeoutIntervalForResource = 3.0
            let session = URLSession(configuration: config)
            
            session.dataTask(with: request) { _, response, error in
                let isReachable = (error == nil && (response as? HTTPURLResponse)?.statusCode == 200)
                if let error = error {
                    print("DEBUG: Probe Failed for \(url.host ?? ""): \(error.localizedDescription)")
                }
                completion(isReachable)
            }.resume()
        }
        
        // Step 1: Probe Primary
        probe(url: primaryURL) { [weak self] success in
            guard let self = self else { return }
            
            if success {
                self.finalizeConnectionStatus(true)
                return
            }
            
            // Step 2: Probe Fallback
            print("DEBUG: Primary Probe Failed. Trying Fallback...")
            probe(url: fallbackURL) { [weak self] successFallback in
                guard let self = self else { return }
                
                if successFallback {
                    self.finalizeConnectionStatus(true)
                    return
                }
                
                // Step 3: Retry Logic (Recursive)
                // If both failed, we check if we should retry the whole chain
                if attempt < 3 { // Increased to 3 attempts (Total 6 probes)
                    print("DEBUG: Both Probes Failed (Attempt \(attempt)). Retrying in 2s...")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                        self.performPingCheck(attempt: attempt + 1)
                    }
                } else {
                    print("DEBUG: All Probes Failed after \(attempt) attempts. Marking OFFLINE.")
                    self.finalizeConnectionStatus(false)
                }
            }
        }
    }
    
    private func finalizeConnectionStatus(_ isOnline: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.isConnected != isOnline {
                print("DEBUG: NetworkMonitor - Status CHANGE: \(self.isConnected) -> \(isOnline)")
            }
            
            self.isConnected = isOnline
            
            if !isOnline {
                self.startRecoveryPolling()
            } else {
                self.stopRecoveryPolling()
            }
        }
    }
    
    deinit {
        monitor.cancel()
    }
}
