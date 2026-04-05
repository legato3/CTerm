import XCTest
@testable import CTerm

@MainActor
final class AgentProfileStoreCustomTests: XCTestCase {

    private var tempDir: URL!
    private var storageURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cterm-profile-custom-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storageURL = tempDir.appendingPathComponent("profiles.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Create via UI-equivalent flow

    func test_addCustomProfile_showsUpAndPersists() {
        let store = AgentProfileStore(storageURL: storageURL)
        let profile = AgentProfile(
            name: "My UI Profile",
            description: "Created via UI flow",
            icon: "hammer",
            trustMode: .askMe,
            autoApproveCategories: [.readFiles, .gitOperations],
            blockedCategories: [.deleteFiles],
            maxRiskTier: .medium,
            isBuiltIn: false
        )
        XCTAssertTrue(store.add(profile))
        XCTAssertTrue(store.profiles.contains(where: { $0.id == profile.id }))

        let reloaded = AgentProfileStore(storageURL: storageURL)
        let found = reloaded.profile(id: profile.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "My UI Profile")
        XCTAssertEqual(found?.icon, "hammer")
        XCTAssertEqual(found?.autoApproveCategories, [.readFiles, .gitOperations])
        XCTAssertEqual(found?.blockedCategories, [.deleteFiles])
        XCTAssertEqual(found?.maxRiskTier, .medium)
        XCTAssertFalse(found?.isBuiltIn ?? true)
    }

    // MARK: - Update custom

    func test_updateCustomProfile_persists() throws {
        let store = AgentProfileStore(storageURL: storageURL)
        var profile = AgentProfile(
            name: "Before",
            description: "",
            icon: "star",
            trustMode: .askMe,
            autoApproveCategories: [.readFiles],
            blockedCategories: [],
            maxRiskTier: .low,
            isBuiltIn: false
        )
        _ = store.add(profile)

        profile.name = "After"
        profile.description = "Edited"
        profile.icon = "flame"
        profile.trustMode = .trustSession
        profile.autoApproveCategories = [.readFiles, .writeFiles]
        profile.maxRiskTier = .high
        try store.update(profile)

        let reloaded = AgentProfileStore(storageURL: storageURL)
        let found = reloaded.profile(id: profile.id)
        XCTAssertEqual(found?.name, "After")
        XCTAssertEqual(found?.description, "Edited")
        XCTAssertEqual(found?.icon, "flame")
        XCTAssertEqual(found?.trustMode, .trustSession)
        XCTAssertEqual(found?.autoApproveCategories, [.readFiles, .writeFiles])
        XCTAssertEqual(found?.maxRiskTier, .high)
    }

    // MARK: - Delete custom

    func test_deleteCustomProfile_removesFromDisk() throws {
        let store = AgentProfileStore(storageURL: storageURL)
        let profile = AgentProfile(
            name: "Doomed",
            description: "",
            icon: "trash",
            trustMode: .askMe,
            autoApproveCategories: [],
            blockedCategories: [],
            maxRiskTier: .low,
            isBuiltIn: false
        )
        _ = store.add(profile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))

        try store.delete(id: profile.id)
        XCTAssertFalse(store.profiles.contains(where: { $0.id == profile.id }))

        let reloaded = AgentProfileStore(storageURL: storageURL)
        XCTAssertNil(reloaded.profile(id: profile.id))
    }

    // MARK: - Built-in deletion refused

    func test_deleteBuiltIn_rejected() {
        let store = AgentProfileStore(storageURL: storageURL)
        XCTAssertThrowsError(try store.delete(id: AgentProfile.readOnly.id)) { error in
            XCTAssertEqual(error as? AgentProfileStore.ProfileError, .cannotDeleteBuiltIn)
        }
        XCTAssertTrue(store.profiles.contains(where: { $0.id == AgentProfile.readOnly.id }))
    }

    // MARK: - Duplicate built-in

    func test_duplicateBuiltIn_asCustom_succeeds() {
        let store = AgentProfileStore(storageURL: storageURL)
        let source = AgentProfile.fullAuto
        let copy = AgentProfile(
            name: "\(source.name) Copy",
            description: source.description,
            icon: source.icon,
            trustMode: source.trustMode,
            autoApproveCategories: source.autoApproveCategories,
            blockedCategories: source.blockedCategories,
            maxRiskTier: source.maxRiskTier,
            isBuiltIn: false
        )

        XCTAssertNotEqual(copy.id, source.id, "Duplicate must have a fresh UUID")
        XCTAssertFalse(copy.isBuiltIn)
        XCTAssertTrue(store.add(copy))

        let found = store.profile(id: copy.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.autoApproveCategories, source.autoApproveCategories)
        XCTAssertEqual(found?.maxRiskTier, source.maxRiskTier)
        XCTAssertFalse(found?.isBuiltIn ?? true)

        // Source built-in untouched.
        let originalBuiltIn = store.profile(id: source.id)
        XCTAssertEqual(originalBuiltIn?.isBuiltIn, true)
    }
}
