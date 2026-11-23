import Foundation
import Network

/// A very small HTTP server on this Mac only. Claude connects to http://127.0.0.1:<port>/mcp and sends tool calls as JSON.
final class MCPServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "crate.mcp")
    private let port: UInt16
    private let handle: ([String: Any], @escaping ([String: Any]?) -> Void) -> Void

    init(port: UInt16, handle: @escaping ([String: Any], @escaping ([String: Any]?) -> Void) -> Void) {
        self.port = port; self.handle = handle
    }

    func start() throws {
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: self.queue)
            self.read(conn, Data())
        }
        l.start(queue: queue)
        listener = l
    }

    private func read(_ conn: NWConnection, _ soFar: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buf = soFar
            if let data { buf.append(data) }
            while let (req, used) = Request.parse(buf) {
                buf = buf.subdata(in: used..<buf.count)
                self.answer(conn, req)
            }
            if complete || error != nil { conn.cancel(); return }
            self.read(conn, buf)
        }
    }

    private func send(_ conn: NWConnection, _ status: String, json: [String: Any]? = nil) {
        let body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        var head = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: keep-alive\r\n"
        if json != nil { head += "Content-Type: application/json\r\n" }
        var out = Data((head + "\r\n").utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in })
    }

    private func answer(_ conn: NWConnection, _ req: Request) {
        // Only programs on this Mac may talk to it. A web page in a browser is turned away.
        if let origin = req.headers["origin"], !origin.hasPrefix("http://localhost"), !origin.hasPrefix("http://127.0.0.1") { send(conn, "403 Forbidden"); return }
        guard req.path == "/mcp" || req.path == "/mcp/" else { send(conn, "404 Not Found"); return }
        guard req.method == "POST" else { send(conn, "405 Method Not Allowed"); return }
        guard let msg = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] else { send(conn, "400 Bad Request"); return }
        if msg["id"] == nil { handle(msg) { _ in }; send(conn, "202 Accepted"); return }       // a notification: nothing to answer
        handle(msg) { [weak self] reply in self?.queue.async { self?.send(conn, "200 OK", json: reply ?? [:]) } }
    }

    struct Request {
        let method: String, path: String, headers: [String: String], body: Data

        /// Returns a whole request and how many bytes it used, or nil if more data is still on its way.
        static func parse(_ data: Data) -> (Request, Int)? {
            guard let gap = data.range(of: Data("\r\n\r\n".utf8)), let head = String(data: data.subdata(in: 0..<gap.lowerBound), encoding: .utf8) else { return nil }
            let lines = head.components(separatedBy: "\r\n")
            let first = lines[0].split(separator: " ")
            guard first.count >= 2 else { return nil }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() { if let c = line.firstIndex(of: ":") { headers[line[..<c].lowercased()] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces) } }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            let start = gap.upperBound
            guard data.count >= start + length else { return nil }
            let path = String(first[1]).components(separatedBy: "?")[0]
            return (Request(method: String(first[0]), path: path, headers: headers, body: data.subdata(in: start..<(start + length))), start + length)
        }
    }
}
