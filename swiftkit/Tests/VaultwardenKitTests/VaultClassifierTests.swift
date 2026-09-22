import Testing
@testable import VaultwardenKit

@Suite("금고 자동 분류")
struct VaultClassifierTests {
    private let folders = [
        VaultFolder(id: "f-money", name: "금융·결제"),
        VaultFolder(id: "f-gov", name: "정부·공공"),
        VaultFolder(id: "f-server", name: "온프레미스·서버"),
    ]

    @Test("이름 대괄호 표기가 태그가 된다")
    func bracketBecomesTag() {
        let item = VaultItem(id: "1", name: "[게임] 스팀", uri: "https://store.steampowered.com")
        let proposals = VaultClassifier.propose(items: [item], folders: folders)
        #expect(proposals.first?.proposedTags.contains("게임") == true)
    }

    @Test("주소 호스트로 태그를 붙인다")
    func hostBecomesTag() {
        let item = VaultItem(id: "1", name: "회사 저장소", uri: "https://gitlab.ranode.net/x")
        #expect(VaultClassifier.propose(items: [item], folders: folders).first?.proposedTags.contains("개발") == true)
    }

    @Test("미분류 항목만 기존 폴더로 옮긴다")
    func onlyUnfiledItemsMove() {
        let unfiled = VaultItem(id: "1", name: "신한은행", uri: "https://bank.shinhan.com")
        var filed = VaultItem(id: "2", name: "국민카드", uri: "https://kbcard.com")
        filed.folderId = "f-gov"
        let proposals = VaultClassifier.propose(items: [unfiled, filed], folders: folders)
        #expect(proposals.first(where: { $0.itemID == "1" })?.proposedFolderName == "금융·결제")
        #expect(proposals.first(where: { $0.itemID == "2" })?.proposedFolderID == nil)
    }

    @Test("기존 태그는 지우지 않고 덧붙인다")
    func tagsAreOnlyAdded() {
        var item = VaultItem(id: "1", name: "홈택스", uri: "https://hometax.go.kr")
        item.tags = ["직접붙인것"]
        let proposal = VaultClassifier.propose(items: [item], folders: folders).first
        #expect(proposal?.proposedTags.first == "직접붙인것")
        #expect(proposal?.proposedTags.contains("정부·공공") == true)
        #expect(proposal?.addedTags.contains("직접붙인것") == false)
    }

    @Test("바뀔 게 없으면 제안하지 않는다")
    func noProposalWhenNothingChanges() {
        var item = VaultItem(id: "1", type: 2, name: "그냥 메모")
        item.folderId = "f-gov"
        item.tags = ["메모"]
        #expect(VaultClassifier.propose(items: [item], folders: folders).isEmpty)
    }

    @Test("삭제된 항목은 건드리지 않는다")
    func deletedItemsIgnored() {
        var item = VaultItem(id: "1", name: "[게임] 스팀")
        item.deleted = true
        #expect(VaultClassifier.propose(items: [item], folders: folders).isEmpty)
    }

    @Test("폴더 이름을 태그로 베끼지 않는다")
    func folderNamesAreNotCopiedIntoTags() {
        // 폴더에 든 것만으로는 태그가 생기지 않는다 — 태그 축이 폴더 축의 복사본이 되면
        // 축을 둘로 나눈 의미가 없다(실측에서 상위 태그가 전부 폴더 이름이었다).
        var item = VaultItem(id: "1", name: "어느 이름도 규칙에 안 걸리는 항목")
        item.folderId = "f-gov"
        #expect(VaultClassifier.propose(items: [item], folders: folders).isEmpty)
    }

    @Test("정렬용 숫자 표기는 태그가 아니다")
    func numericBracketsIgnored() {
        #expect(VaultClassifier.bracketTags(in: "[99] 게임 런처") == [])
        #expect(VaultClassifier.bracketTags(in: "[99][게임] 런처") == ["게임"])
    }

    @Test("킷이 저장 못 하는 유형(SSH 키)은 제안하지 않는다")
    func unsupportedTypesAreSkipped() {
        // 적용할 수 없는 제안을 올려 두면 매번 실패 건수로만 남는다. 저장 자체도 막혀 있다
        // — 모르는 하위 오브젝트를 안 실어 보내면 개인키가 지워지기 때문.
        let sshKey = VaultItem(id: "1", type: 5, name: "[개발] github-sshkey")
        #expect(VaultClassifier.propose(items: [sshKey], folders: folders).isEmpty)
        #expect(!VaultCipherType.editable.contains(5))
        #expect(VaultCipherType.label(5) == "SSH 키")
    }

    @Test("카드·신원 유형은 유형 태그를 받는다")
    func typeTags() {
        #expect(VaultClassifier.typeTag(3) == "카드")
        #expect(VaultClassifier.typeTag(4) == "신원")
        #expect(VaultClassifier.typeTag(1) == nil)
    }
}
