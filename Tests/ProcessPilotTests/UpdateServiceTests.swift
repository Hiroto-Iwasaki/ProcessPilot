import XCTest
import Foundation
@testable import ProcessPilot

final class UpdateServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.removeAllHandlers()
        super.tearDown()
    }

    @MainActor
    func testCheckForUpdatesSetsAvailableUpdateWhenLatestVersionIsNewer() async throws {
        let context = makeServiceContext(currentVersion: "1.2.0")

        MockURLProtocol.setHandler(for: context.releaseURL) { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                context.releaseURL.absoluteString
            )

            let data = try Self.makeReleaseJSON(
                tagName: "v1.10.0",
                htmlURL: "https://example.com/release/v1.10.0",
                assets: [
                    ("ProcessPilot.zip", "https://example.com/ProcessPilot.zip"),
                    ("ProcessPilot.dmg", "https://example.com/ProcessPilot.dmg")
                ]
            )
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, data)
        }

        await context.service.checkForUpdates()

        XCTAssertEqual(context.service.availableUpdate?.version, "v1.10.0")
        XCTAssertEqual(context.service.availableUpdate?.releaseURL.absoluteString, "https://example.com/release/v1.10.0")
        XCTAssertEqual(context.service.availableUpdate?.downloadURL?.absoluteString, "https://example.com/ProcessPilot.dmg")
    }

    @MainActor
    func testCheckForUpdatesSetsNilWhenLatestVersionIsSameOrOlder() async throws {
        let context = makeServiceContext(currentVersion: "1.2.0")

        MockURLProtocol.setHandler(for: context.releaseURL) { request in
            let data = try Self.makeReleaseJSON(
                tagName: "1.2.0",
                htmlURL: "https://example.com/release/1.2.0",
                assets: []
            )
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, data)
        }

        await context.service.checkForUpdates()
        XCTAssertNil(context.service.availableUpdate)

        MockURLProtocol.setHandler(for: context.releaseURL) { request in
            let data = try Self.makeReleaseJSON(
                tagName: "1.1.9",
                htmlURL: "https://example.com/release/1.1.9",
                assets: []
            )
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, data)
        }

        await context.service.checkForUpdates()
        XCTAssertNil(context.service.availableUpdate)
    }

    @MainActor
    func testPreferredDownloadURLFallsBackToZipThenFirstAsset() async throws {
        let context = makeServiceContext(currentVersion: "1.0.0")

        MockURLProtocol.setHandler(for: context.releaseURL) { request in
            let data = try Self.makeReleaseJSON(
                tagName: "1.1.0",
                htmlURL: "https://example.com/release/1.1.0",
                assets: [
                    ("ProcessPilot.zip", "https://example.com/ProcessPilot.zip"),
                    ("notes.txt", "https://example.com/notes.txt")
                ]
            )
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, data)
        }

        await context.service.checkForUpdates()
        XCTAssertEqual(context.service.availableUpdate?.downloadURL?.absoluteString, "https://example.com/ProcessPilot.zip")

        MockURLProtocol.setHandler(for: context.releaseURL) { request in
            let data = try Self.makeReleaseJSON(
                tagName: "1.2.0",
                htmlURL: "https://example.com/release/1.2.0",
                assets: [
                    ("notes.txt", "https://example.com/notes.txt"),
                    ("manual.pdf", "https://example.com/manual.pdf")
                ]
            )
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, data)
        }

        await context.service.checkForUpdates()
        XCTAssertEqual(context.service.availableUpdate?.downloadURL?.absoluteString, "https://example.com/notes.txt")
    }

    @MainActor
    func testCheckForUpdatesClearsAvailableUpdateOnHTTPError() async throws {
        let context = makeServiceContext(currentVersion: "1.0.0")

        MockURLProtocol.setHandler(for: context.releaseURL) { request in
            let data = try Self.makeReleaseJSON(
                tagName: "1.1.0",
                htmlURL: "https://example.com/release/1.1.0",
                assets: [("ProcessPilot.dmg", "https://example.com/ProcessPilot.dmg")]
            )
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, data)
        }

        await context.service.checkForUpdates()
        XCTAssertNotNil(context.service.availableUpdate)

        MockURLProtocol.setHandler(for: context.releaseURL) { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("{}".utf8))
        }

        await context.service.checkForUpdates()
        XCTAssertNil(context.service.availableUpdate)
    }

    @MainActor
    private func makeServiceContext(currentVersion: String) -> ServiceContext {
        let owner = "test-owner"
        let repo = "test-repo-\(UUID().uuidString.lowercased())"

        let service = UpdateService(
            session: makeMockedSession(),
            owner: owner,
            repo: repo,
            currentVersionString: currentVersion,
            shouldCheckOnInit: false,
            logHandler: { _ in }
        )

        return ServiceContext(
            service: service,
            releaseURL: makeLatestReleaseURL(owner: owner, repo: repo)
        )
    }

    private func makeMockedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeLatestReleaseURL(owner: String, repo: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }

    private static func makeReleaseJSON(
        tagName: String,
        htmlURL: String,
        assets: [(name: String, url: String)]
    ) throws -> Data {
        let payload: [String: Any] = [
            "tag_name": tagName,
            "html_url": htmlURL,
            "assets": assets.map { asset in
                [
                    "name": asset.name,
                    "browser_download_url": asset.url
                ]
            }
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private struct ServiceContext {
        let service: UpdateService
        let releaseURL: URL
    }
}

private final class MockURLProtocol: URLProtocol {
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handlersByURL: [String: RequestHandler] = [:]

    static func setHandler(for url: URL, handler: @escaping RequestHandler) {
        lock.lock()
        handlersByURL[url.absoluteString] = handler
        lock.unlock()
    }

    static func removeAllHandlers() {
        lock.lock()
        handlersByURL.removeAll()
        lock.unlock()
    }

    private static func handler(for request: URLRequest) -> RequestHandler? {
        guard let absoluteURL = request.url?.absoluteString else {
            return nil
        }

        lock.lock()
        let handler = handlersByURL[absoluteURL]
        lock.unlock()
        return handler
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
