import XCTest
import SwiftData
@testable import SubscriptionWallet

@MainActor final class RepositoryTests: XCTestCase {
    func make(_ name: String = "测试") -> Subscription { var s=Subscription();s.name=name;s.category = .other;return s }
    func testUniqueServiceIDIncludingArchive() throws {
        let repo=try WalletRepository(container:WalletRepository.container(inMemory:true));var a=make();a.serviceID="qq_music";try repo.save(a);try repo.setArchived(a,true)
        var b=make("duplicate");b.serviceID="qq_music";XCTAssertThrowsError(try repo.save(b));XCTAssertEqual(repo.records.count,1);XCTAssertTrue(repo.records[0].isArchived)
    }
    func testReloadSavedData() throws { let container=try WalletRepository.container(inMemory:true);let repo=try WalletRepository(container:container);let a=make();try repo.save(a);let reopened=try WalletRepository(container:container);XCTAssertEqual(reopened.records.first?.name,a.name) }
    func testValidationLeavesOriginalUnchanged() throws { let repo=try WalletRepository(container:WalletRepository.container(inMemory:true));let a=make();try repo.save(a);var invalid=a;invalid.name="";XCTAssertThrowsError(try repo.save(invalid));try repo.reload();XCTAssertEqual(repo.records.first?.name,a.name) }
    func testDeleteParentDetachesAndKeepsSourceName() throws { let repo=try WalletRepository(container:WalletRepository.container(inMemory:true));let a=make("88VIP");try repo.save(a);var b=make("优酷");b.acquisition = .bundled;b.sourceSubscriptionID=a.id;try repo.save(b);try repo.delete(a);XCTAssertEqual(repo.records.count,1);XCTAssertNil(repo.records[0].sourceSubscriptionID);XCTAssertEqual(repo.records[0].sourceName,"88VIP") }
    func testChangingParentSourceDetachesChildren() throws { let repo=try WalletRepository(container:WalletRepository.container(inMemory:true));var a=make("88VIP");try repo.save(a);var b=make("优酷");b.acquisition = .bundled;b.sourceSubscriptionID=a.id;try repo.save(b);a.acquisition = .gifted;try repo.save(a);XCTAssertNil(repo.records.first { $0.id==b.id }?.sourceSubscriptionID) }
    func testPreferencesPersist() throws { let c=try WalletRepository.container(inMemory:true);let repo=try WalletRepository(container:c);var p=Preferences();p.exchangeRates["USD"]="7.2";p.notificationShowsServiceName=false;try repo.savePreferences(p);let reopened=try WalletRepository(container:c);XCTAssertEqual(reopened.preferences,p) }
    func testDiskStoreAcrossContainerRecreation() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let url=directory.appendingPathComponent("wallet.store")
        var repo: WalletRepository?=try WalletRepository(container:WalletRepository.container(storeURL:url))
        let record=make("磁盘保存");try repo!.save(record);repo=nil
        let reopened=try WalletRepository(container:WalletRepository.container(storeURL:url))
        XCTAssertEqual(reopened.records.first?.id,record.id)
    }
}
