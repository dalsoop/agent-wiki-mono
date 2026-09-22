import Foundation
import Testing
import ProductPortfolioKit

@Suite("Portfolio deep links")
struct PortfolioDeepLinkTests {
    @Test("builds product-portfolio URL with destination host and slug path")
    func buildsURL() throws {
        let link = try PortfolioDeepLink(destination: .evaluation, slug: "agent-browser-swift")
        #expect(link.url.scheme == "product-portfolio")
        #expect(link.url.host == "evaluation")
        #expect(link.url.path == "/agent-browser-swift")
        #expect(link.destination.bundleIdentifier == "net.ranode.productevaluationstudio")
    }

    @Test("parses path and query forms")
    func parses() throws {
        let pathURL = URL(string: "product-portfolio://feedback/flowlog-swift")!
        let path = PortfolioDeepLink(url: pathURL)
        #expect(path?.destination == .feedback)
        #expect(path?.slug == "flowlog-swift")

        let queryURL = URL(string: "product-portfolio://backlog?slug=screenshot-swift")!
        let query = PortfolioDeepLink(url: queryURL)
        #expect(query?.destination == .backlog)
        #expect(query?.slug == "screenshot-swift")
    }

    @Test("rejects invalid scheme host or slug")
    func rejectsInvalid() {
        #expect(PortfolioDeepLink(url: URL(string: "https://example.com/x")!) == nil)
        #expect(PortfolioDeepLink(url: URL(string: "product-portfolio://unknown/x")!) == nil)
        #expect(throws: PortfolioDeepLinkError.self) {
            _ = try PortfolioDeepLink(destination: .evaluation, slug: "../Bad App")
        }
        #expect(throws: PortfolioDeepLinkError.self) {
            _ = try PortfolioDeepLink(destination: .evaluation, slug: "  ")
        }
    }

    @Test("normalizes slug to lowercase")
    func normalizes() throws {
        let link = try PortfolioDeepLink(destination: .evaluation, slug: " Agent-Browser-Swift ")
        #expect(link.slug == "agent-browser-swift")
    }
}
