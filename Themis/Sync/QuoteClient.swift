import Foundation

enum QuoteClient {
    /// Nil when offline, timed out, or rate-limited, so the UI simply hides the quote.
    static func fetch() async -> Quote? {
        guard let url = URL(string: "https://zenquotes.io/api/random") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue("themis-mobile", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let o = arr.first,
                  let q = (o["q"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let a = (o["a"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            else { return nil }
            if q.isEmpty || a.lowercased() == "zenquotes.io" { return nil }
            return Quote(text: q, author: a)
        } catch { return nil }
    }
}
