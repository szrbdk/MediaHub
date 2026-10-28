import Foundation
import OSLog

final class MediaClient {
    private var connection: NSXPCConnection?
    private let logger = Logger(subsystem: "com.sezerbudak.MediaHub", category: "MediaRemote")

    private func proxy(onError: @escaping () -> Void) -> MediaServiceProtocol? {
        if connection == nil {
            let connection = NSXPCConnection(serviceName: "com.apple.sezerbudak.MediaHub.MediaService")
            connection.remoteObjectInterface = NSXPCInterface(with: MediaServiceProtocol.self)
            connection.interruptionHandler = { [weak self] in
                self?.logger.error("Media service interrupted; the next request will reconnect")
            }
            connection.invalidationHandler = { [weak self] in
                DispatchQueue.main.async { self?.connection = nil }
            }
            connection.resume()
            self.connection = connection
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.logger.error("Media service error: \(error.localizedDescription, privacy: .public)")
            onError()
        } as? MediaServiceProtocol
    }

    // XPC transport errors do not invoke the service's reply block. Deliver a
    // single bounded completion in either case so polling and quitting cannot hang.
    private func request<Value>(fallback: Value,
                                completion: @escaping (Value) -> Void,
                                operation: (MediaServiceProtocol, @escaping (Value) -> Void) -> Void) {
        var finished = false
        let finish: (Value) -> Void = { value in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(value)
            }
        }
        guard let service = proxy(onError: { finish(fallback) }) else { finish(fallback); return }
        operation(service, finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { finish(fallback) }
    }

    func read(completion: @escaping ([String: Any]?) -> Void) {
        request(fallback: nil as [String: Any]?, completion: completion) { service, finish in
            service.readState { [weak self] payload, error in
                if let error { self?.logger.error("\(error, privacy: .public)") }
                finish(payload as? [String: Any])
            }
        }
    }

    func send(_ command: Int, completion: @escaping (Bool) -> Void = { _ in }) {
        request(fallback: false, completion: completion) { service, finish in
            service.sendCommand(command, reply: finish)
        }
    }

    func seek(seconds: Double, completion: @escaping (Bool) -> Void) {
        request(fallback: false, completion: completion) { service, finish in
            service.seek(toPosition: seconds, reply: finish)
        }
    }

    func stop(completion: @escaping () -> Void) {
        request(fallback: false, completion: { [self] _ in
            invalidate()
            completion()
        }) { service, finish in
            service.flush { finish(true) }
        }
    }

    private func invalidate() {
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate()
        connection = nil
    }
}
