import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

@Suite struct WikiWorldLayerTests {
    @Test func classifiesPersonWorldsAsLocalEvenIfNameLooksLikeRepo() {
        #expect(
            WikiWorldPresentation.classify(
                name: "person-family",
                rootPath: "/Users/x/.tenants/family/wiki"
            ) == .localPerson
        )
        #expect(
            WikiWorldPresentation.classify(
                name: "odd",
                rootPath: "/Users/x/.tenants/personal/wiki"
            ) == .localPerson
        )
    }

    @Test func classifiesGujoAsRemoteEvenWhenPathIsAGitCheckout() {
        #expect(
            WikiWorldPresentation.classify(
                name: "gujo-wiki",
                rootPath: "/Users/x/gujo-wiki"
            ) == .remoteShared
        )
    }

    @Test func classifiesRepoWikiAndTopicLedgers() {
        #expect(
            WikiWorldPresentation.classify(
                name: "swift-app-mono",
                rootPath: "/src/swift-app-mono/.wiki"
            ) == .repository
        )
        #expect(
            WikiWorldPresentation.classify(
                name: "gov-programs",
                rootPath: "/Users/x/gov-programs-wiki"
            ) == .other
        )
    }

    @Test func titlesSeparateLocalTenantFromRemote() {
        #expect(
            WikiWorldPresentation.title(
                name: "person-personal",
                rootPath: "/Users/x/.tenants/personal/wiki"
            ) == "본인 · 로컬 1인칭"
        )
        #expect(
            WikiWorldPresentation.title(
                name: "gujo-wiki",
                rootPath: "/Users/x/gujo-wiki"
            ) == "공유 위키 · 원격"
        )
        let personSub = WikiWorldPresentation.subtitle(
            name: "person-silneobal",
            rootPath: "/Users/x/.tenants/silneobal/wiki"
        )
        #expect(personSub.contains("GitLab 441에 안 올라감"))
        let remoteSub = WikiWorldPresentation.subtitle(
            name: "gujo-wiki",
            rootPath: "/Users/x/gujo-wiki"
        )
        #expect(remoteSub.contains(GujoWikiWeb.projectURL))
    }

    @Test func listItemsGroupLocalThenRemote() {
        let items = WikiWorldPresentation.listItems(
            worlds: [
                LedgerWorld(name: "gujo-wiki", rootPath: "/Users/x/gujo-wiki"),
                LedgerWorld(name: "person-family", rootPath: "/Users/x/.tenants/family/wiki"),
                LedgerWorld(name: "mono", rootPath: "/src/mono/.wiki"),
            ],
            selectedName: "person-family"
        )
        #expect(items.map(\.layer) == [.localPerson, .remoteShared, .repository])
        #expect(items.first?.selected ?? false)
        let text = WikiWorldPresentation.plainText(items: items)
        #expect(text.contains("로컬 1인칭"))
        #expect(text.contains("원격 공유 위키"))
    }

    @Test func tenantLayerHasTitles() {
        #expect(WikiWorldLayer.tenant.groupTitle == "테넌트 위키")
        #expect(WikiWorldLayer.tenant.badge == "테넌트")
        #expect(WikiWorldLayer.tenant.systemImage == "building.2")
        #expect(WikiWorldLayer.tenant.sortIndex == 1)
        #expect(WikiWorldLayer.allCases.contains(.tenant))
    }

    @Test func infersPersonWorldFromTenantID() {
        #expect(
            WikiWorldPresentation.inferredPersonWorld(
                tenantID: "tenant:family",
                contextURL: URL(fileURLWithPath: "/no-such.json")
            ) == "person-family"
        )
        #expect(
            WikiWorldPresentation.inferredPersonWorld(
                tenantID: nil,
                contextURL: URL(fileURLWithPath: "/no-such.json")
            ) == "person-personal"
        )
    }
}
