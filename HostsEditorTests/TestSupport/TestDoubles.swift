import Foundation
import ServiceManagement
@testable import HostsEditor

/// 模拟特权 Helper：把写入内容保存在内存里，可注入错误、延迟和写后篡改
@MainActor
final class FakePrivilegedHostsWriter: PrivilegedHostsWriting {
    var daemonStatus: SMAppService.Status = .enabled
    var isHelperInstalled = true
    var isHelperExplicitlyDisabled = false
    var hasRegisteredHelper = true

    /// 模拟的 /etc/hosts 当前内容
    var hostsContent: String
    private(set) var writtenContents: [String] = []
    var errorToThrow: Error?
    var writeDelayNanoseconds: UInt64 = 0
    /// 写入后对落盘内容做变换，用于模拟写入校验失败
    var tamper: ((String) -> String)?

    init(hostsContent: String = "") {
        self.hostsContent = hostsContent
    }

    func writeHosts(content: String) async throws {
        if writeDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: writeDelayNanoseconds)
        }
        if let errorToThrow {
            throw errorToThrow
        }
        writtenContents.append(content)
        hostsContent = tamper?(content) ?? content
    }

    func enableHelper() async throws {}
    func uninstallHelperAndWait() async throws {}
    func reinstallHelper() async throws {}
}

/// 拦截 URLSession 请求，按测试设定返回响应
final class StubURLProtocol: URLProtocol {
    struct StubResponse {
        var statusCode: Int = 200
        var mimeType: String = "text/plain"
        var body: Data = Data()
        var error: Error?
    }

    nonisolated(unsafe) static var responder: ((URLRequest) -> StubResponse)?
    nonisolated(unsafe) static var requestCount = 0

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        responder = nil
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        let stub = Self.responder?(request) ?? StubResponse(statusCode: 404)
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.test")!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": stub.mimeType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// 创建一个独立的临时目录，测试结束后由调用方删除
func makeTemporaryDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// 在回调闭包里记录值的简单容器
final class ValueBox<Value>: @unchecked Sendable {
    var value: Value?
}
