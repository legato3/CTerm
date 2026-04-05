import XCTest
@testable import CTerm

@MainActor
final class AgentProfileStoreTests: XCTestCase {

    private var tempDir: URL!
    private var storageURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cterm-profile-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storageURL = tempDir.appendingPathComponent("profiles.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_builtInsPresentOnInit() {
        let store = AgentProfileStore(storageURL: storageURL)
        XCTAssertEqual(store.profiles.count, AgentProfile.builtIns.count)
        XCTAssertTrue(store.profiles.contains(where: { $0.id == AgentProfile.readOnly.id }))
        XCTAssertTrue(store.profiles.contains(where: { $0.id == AgentProfile.sandboxRepo.id }))
        XCTAssertTrue(store.profiles.contains(where: { $0.id == AgentProfile.standard.id }))
        XCTAssertTrue(store.profiles.contains(where: { $0.id == AgentProfile.fullAuto.id }))
    }

    func test_activeProfileDefaultsToStandard() {
        let store = AgentProfileStore(storageURL: storageURL)
        XCTAssertEqual(store.activeProfile.id, AgentProfile.standard.id)
    }

    func test_activeProfileHonorsActiveID() {
        let store = AgentProfileStore(storageURL: storageURL)
        store.activeProfileID = AgentProfile.fullAuto.id
        XCTAssertEqual(store.activeProfile.id, AgentProfile.fullAuto.id)
        XCTAssertEqual(store.activeProfile.name, "Full Auto")
    }

    func test_addCustomPersistsAndReloads() {
        let store = AgentProfileStore(storageURL: storageURL)
        let custom = AgentProfile(
            name: "My Custom",
            description: "Test profile",
            icon: "star",
            trustMode: .askMe,
            autoApproveCategories: [.readFiles],
            blockedCategories: [],
            maxRiskTier: .medium,
            isBuiltIn: false
        )
        XCTAssertTrue(store.add(custom))
        XCTAssertTrue(store.profiles.contains(where: { $0.id == custom.id }))

        // Reload from disk
        let reloaded = AgentProfileStore(storageURL: storageURL)
        XCTAssertTrue(reloaded.profiles.contains(where: { $0.id == custom.id }))
    }

    func test_deleteCustomSucceeds() throws {
        let store = AgentProfileStore(storageURL: storageURL)
        let custom = AgentProfile(
            name: "Doomed",
            description: "Will be deleted",
            icon: "trash",
            trustMode: .askMe,
            autoApproveCategories: [],
            blockedCategories: [],
            maxRiskTier: .low,
            isBuiltIn: false
        )
        _ = store.add(custom)
        try store.delete(id: custom.id)
        XCTAssertFalse(store.profiles.contains(where: { $0.id == custom.id }))
    }

    func test_deleteBuiltInThrows() {
        let store = AgentProfileStore(storageURL: storageURL)
        XCTAssertThrowsError(try store.delete(id: AgentProfile.standard.id)) { error in
            XCTAssertEqual(error as? AgentProfileStore.ProfileError, .cannotDeleteBuiltIn)
        }
        XCTAssertTrue(store.profiles.contains(where: { $0.id == AgentProfile.standard.id }))
    }

    func test_addRejectsBuiltIn() {
        let store = AgentProfileStore(storageURL: storageURL)
        XCTAssertFalse(store.add(AgentProfile.standard))
    }

    func test_deleteActiveProfileResetsToStandard() throws {
        let store = AgentProfileStore(storageURL: storageURL)
        let custom = AgentProfile(
            name: "Active",
            description: "",
            icon: "circle",
            trustMode: .askMe,
            autoApproveCategories: [],
            blockedCategories: [],
            maxRiskTier: .low,
            isBuiltIn: false
        )
        _ = store.add(custom)
        store.activeProfileID = custom.id
        try store.delete(id: custom.id)
        XCTAssertEqual(store.activeProfileID, AgentProfile.standard.id)
    }
}
