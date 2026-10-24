import Foundation
import Darwin

/// UDP discovery: broadcast THEMIS_DISCOVERY_PING and wait up to 3 s for the desktop's JSON reply.
///
/// iOS note: sending to broadcast addresses needs the Local Network permission (the app asks for it) and, on
/// some iOS versions, Apple's multicast-networking entitlement. When discovery cannot reach the desktop the app
/// falls back to the manual desktop address that can be typed on the Dashboard.
enum Discovery {
    private static let port: UInt16 = 54321
    private static let timeoutSeconds = 3.0

    static func find() async -> DesktopHost? {
        await Task.detached(priority: .utility) { findBlocking() }.value
    }

    private static func findBlocking() -> DesktopHost? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        let ping = Array("THEMIS_DISCOVERY_PING".utf8)
        let targets = Array(Set(["255.255.255.255"] + subnetBroadcasts()))
        for target in targets {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            guard inet_pton(AF_INET, target, &addr.sin_addr) == 1 else { continue }
            _ = withUnsafePointer(to: &addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    sendto(fd, ping, ping.count, 0, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var buffer = [UInt8](repeating: 0, count: 2048)
        while Date() < deadline {
            let remaining = max(deadline.timeIntervalSinceNow, 0.05)
            var tv = timeval(tv_sec: Int(remaining), tv_usec: Int32((remaining - floor(remaining)) * 1_000_000))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    recvfrom(fd, &buffer, buffer.count, 0, sp, &fromLen)
                }
            }
            if n <= 0 { return nil }   // timed out (or error)

            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sinAddr = from.sin_addr
            guard inet_ntop(AF_INET, &sinAddr, &ipBuf, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ip = String(cString: ipBuf)
            let data = Data(buffer[0..<n])
            if let host = parse(data, host: ip) { return host }
        }
        return nil
    }

    private static func parse(_ data: Data, host: String) -> DesktopHost? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (o["app"] as? String) == "Themis", (o["role"] as? String) == "desktop" else { return nil }
        if let p = o["port"] as? Int { return DesktopHost(host: host, port: p) }
        if let p = (o["port"] as? NSNumber)?.intValue { return DesktopHost(host: host, port: p) }
        return nil
    }

    /// Each interface's subnet broadcast (some routers drop 255.255.255.255).
    private static func subnetBroadcasts() -> [String] {
        var result: [String] = []
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return [] }
        defer { freeifaddrs(addrs) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            let flags = Int32(ifa.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_BROADCAST) != 0, (flags & IFF_LOOPBACK) == 0,
               let dst = ifa.ifa_dstaddr, dst.pointee.sa_family == sa_family_t(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(dst, socklen_t(dst.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    result.append(String(cString: host))
                }
            }
            ptr = ifa.ifa_next
        }
        return result
    }
}
