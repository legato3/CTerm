//
//  SplitTreeTests.swift
//  CTermTests
//
//  Tests for the SplitTree model — a pure value type representing
//  the split layout of terminal panes.
//
//  Coverage:
//  - Insert leaf (single → split with 2 leaves)
//  - Remove leaf (collapse parent, verify focus target)
//  - Focus navigation (next/previous with wrap-around)
//  - Equalize (all ratios become 0.5)
//  - Codable roundtrip
//  - Edge: remove last leaf → nil root, nil focus
//  - Ratio clamping to [0.1, 0.9]
//  - Nested splits (insert into already-split tree)
//  - allLeafIDs returns all leaf IDs in order
//

import XCTest
@testable import CTerm

final class SplitTreeTests: XCTestCase {

    // MARK: - Helpers

    /// Build a tree with a single leaf.
    private func makeSingleLeafTree() -> (SplitTree, UUID) {
        let id = UUID()
        let tree = SplitTree(root: .leaf(id: id), focusedLeafID: id)
        return (tree, id)
    }

    // ==================== 1. Insert Leaf ====================

    func test_should_create_split_with_two_leaves_when_inserting_into_single_leaf() {
        // Arrange
        let (tree, originalID) = makeSingleLeafTree()

        // Act
        let (newTree, newLeafID) = tree.insert(at: originalID, direction: .horizontal)

        // Assert — root must now be a split, not a leaf
        guard case .split(let data) = newTree.root else {
            XCTFail("Expected root to be a split after insert, got leaf or nil")
            return
        }

        XCTAssertEqual(data.direction, .horizontal)
        XCTAssertEqual(data.ratio, 0.5, "Default split ratio should be 0.5")

        // The original leaf and the new leaf should appear as children
        guard case .leaf(let firstID) = data.first,
              case .leaf(let secondID) = data.second else {
            XCTFail("Expected both children to be leaves")
            return
        }

        XCTAssertEqual(firstID, originalID, "First child should be the original leaf")
        XCTAssertEqual(secondID, newLeafID, "Second child should be the newly created leaf")
        XCTAssertNotEqual(originalID, newLeafID, "New leaf must have a distinct UUID")
    }

    func test_should_split_vertically_when_vertical_direction_specified() {
        let (tree, leafID) = makeSingleLeafTree()

        let (newTree, _) = tree.insert(at: leafID, direction: .vertical)

        guard case .split(let data) = newTree.root else {
            XCTFail("Expected root to be a split after vertical insert")
            return
        }
        XCTAssertEqual(data.direction, .vertical)
    }

    // ==================== 2. Remove Leaf ====================

    func test_should_collapse_parent_split_when_removing_one_of_two_leaves() {
        // Arrange — start with a single leaf, split it, then remove the new leaf
        let (tree, originalID) = makeSingleLeafTree()
        let (splitTree, newLeafID) = tree.insert(at: originalID, direction: .horizontal)

        // Act — remove the new leaf; the parent split should collapse
        let (result, focusTarget) = splitTree.remove(newLeafID)

        // Assert — root should revert to the original single leaf
        guard case .leaf(let remainingID) = result.root else {
            XCTFail("Expected root to collapse back to a single leaf")
            return
        }
        XCTAssertEqual(remainingID, originalID)
        XCTAssertEqual(focusTarget, originalID, "Focus should move to the remaining leaf")
    }

    func test_should_return_sibling_as_focus_target_when_removing_first_child() {
        let (tree, originalID) = makeSingleLeafTree()
        let (splitTree, newLeafID) = tree.insert(at: originalID, direction: .horizontal)

        // Remove the original (first) leaf
        let (result, focusTarget) = splitTree.remove(originalID)

        guard case .leaf(let remainingID) = result.root else {
            XCTFail("Expected root to collapse back to a single leaf")
            return
        }
        XCTAssertEqual(remainingID, newLeafID)
        XCTAssertEqual(focusTarget, newLeafID, "Focus should move to the remaining sibling")
    }

    // ==================== 3. Focus Navigation ====================

    func test_should_navigate_to_next_leaf_in_order() {
        // Arrange — create a tree with 3 leaves: A | B | C
        let (tree, idA) = makeSingleLeafTree()
        let (tree2, idB) = tree.insert(at: idA, direction: .horizontal)
        let (tree3, idC) = tree2.insert(at: idB, direction: .horizontal)

        let allIDs = tree3.allLeafIDs()
        XCTAssertEqual(allIDs.count, 3, "Should have 3 leaves")

        // Act — from the first leaf, navigate next
        let nextFromA = tree3.focusTarget(for: .next, from: idA)
        XCTAssertEqual(nextFromA, idB, "Next from first leaf should be second leaf")
    }

    func test_should_navigate_to_previous_leaf_in_order() {
        let (tree, idA) = makeSingleLeafTree()
        let (tree2, idB) = tree.insert(at: idA, direction: .horizontal)
        let (tree3, _) = tree2.insert(at: idB, direction: .horizontal)

        let prevFromB = tree3.focusTarget(for: .previous, from: idB)
        XCTAssertEqual(prevFromB, idA, "Previous from second leaf should be first leaf")
    }

    func test_should_wrap_around_when_navigating_next_from_last_leaf() {
        let (tree, idA) = makeSingleLeafTree()
        let (tree2, idB) = tree.insert(at: idA, direction: .horizontal)

        // idB is the last leaf; next should wrap to idA
        let wrapped = tree2.focusTarget(for: .next, from: idB)
        XCTAssertEqual(wrapped, idA, "Next from last leaf should wrap to the first leaf")
    }

    func test_should_wrap_around_when_navigating_previous_from_first_leaf() {
        let (tree, idA) = makeSingleLeafTree()
        let (tree2, idB) = tree.insert(at: idA, direction: .horizontal)

        let wrapped = tree2.focusTarget(for: .previous, from: idA)
        XCTAssertEqual(wrapped, idB, "Previous from first leaf should wrap to the last leaf")
    }

    // ==================== 4. Equalize ====================

    func test_should_set_all_ratios_to_half_when_equalized() {
        // Arrange — build a tree with unequal ratios via nested splits
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()

        let innerSplit = SplitNode.split(SplitData(
            direction: .horizontal,
            ratio: 0.3,
            first: .leaf(id: idB),
            second: .leaf(id: idC)
        ))
        let root = SplitNode.split(SplitData(
            direction: .vertical,
            ratio: 0.7,
            first: .leaf(id: idA),
            second: innerSplit
        ))
        let tree = SplitTree(root: root, focusedLeafID: idA)

        // Act
        let equalized = tree.equalize()

        // Assert — recursively verify all ratios are 0.5
        func verifyRatios(_ node: SplitNode) {
            switch node {
            case .leaf:
                break
            case .split(let data):
                XCTAssertEqual(data.ratio, 0.5, accuracy: 0.001,
                               "All ratios should be 0.5 after equalize")
                verifyRatios(data.first)
                verifyRatios(data.second)
            }
        }

        if let root = equalized.root {
            verifyRatios(root)
        } else {
            XCTFail("Root should not be nil after equalize")
        }
    }

    func test_should_preserve_directions_when_equalized() {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()

        let innerSplit = SplitNode.split(SplitData(
            direction: .horizontal,
            ratio: 0.3,
            first: .leaf(id: idB),
            second: .leaf(id: idC)
        ))
        let root = SplitNode.split(SplitData(
            direction: .vertical,
            ratio: 0.7,
            first: .leaf(id: idA),
            second: innerSplit
        ))
        let tree = SplitTree(root: root, focusedLeafID: idA)

        let equalized = tree.equalize()

        guard case .split(let outerData) = equalized.root else {
            XCTFail("Root should be a split")
            return
        }
        XCTAssertEqual(outerData.direction, .vertical, "Outer direction preserved")

        guard case .split(let innerData) = outerData.second else {
            XCTFail("Second child should be a split")
            return
        }
        XCTAssertEqual(innerData.direction, .horizontal, "Inner direction preserved")
    }

    // ==================== 5. Codable Roundtrip ====================

    func test_should_survive_codable_roundtrip_for_single_leaf() throws {
        let (tree, _) = makeSingleLeafTree()

        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitTree.self, from: data)

        XCTAssertEqual(decoded, tree, "Decoded tree should equal original")
    }

    func test_should_survive_codable_roundtrip_for_nested_split() throws {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()

        let innerSplit = SplitNode.split(SplitData(
            direction: .horizontal,
            ratio: 0.4,
            first: .leaf(id: idB),
            second: .leaf(id: idC)
        ))
        let root = SplitNode.split(SplitData(
            direction: .vertical,
            ratio: 0.6,
            first: .leaf(id: idA),
            second: innerSplit
        ))
        let tree = SplitTree(root: root, focusedLeafID: idA)

        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitTree.self, from: data)

        XCTAssertEqual(decoded, tree, "Complex tree should survive Codable roundtrip")
    }

    func test_should_survive_codable_roundtrip_for_nil_root() throws {
        let tree = SplitTree(root: nil, focusedLeafID: nil)

        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitTree.self, from: data)

        XCTAssertEqual(decoded, tree, "Empty tree should survive Codable roundtrip")
    }

    // ==================== 6. Edge: Remove Last Leaf ====================

    func test_should_return_nil_root_when_removing_the_only_leaf() {
        let (tree, onlyID) = makeSingleLeafTree()

        let (result, focusTarget) = tree.remove(onlyID)

        XCTAssertNil(result.root, "Root should be nil after removing the only leaf")
        XCTAssertNil(focusTarget, "Focus target should be nil when no leaves remain")
    }

    func test_should_return_nil_focused_leaf_when_removing_last_leaf() {
        let (tree, onlyID) = makeSingleLeafTree()

        let (result, _) = tree.remove(onlyID)

        XCTAssertNil(result.focusedLeafID, "focusedLeafID should be nil when tree is empty")
    }

    // ==================== 7. Ratio Clamping ====================

    func test_should_clamp_ratio_to_minimum_when_below_threshold() {
        let idA = UUID()
        let idB = UUID()

        let data = SplitData(
            direction: .horizontal,
            ratio: 0.0,  // below minimum of 0.1
            first: .leaf(id: idA),
            second: .leaf(id: idB)
        )

        XCTAssertGreaterThanOrEqual(data.ratio, 0.1,
                                     "Ratio should be clamped to at least 0.1")
    }

    func test_should_clamp_ratio_to_maximum_when_above_threshold() {
        let idA = UUID()
        let idB = UUID()

        let data = SplitData(
            direction: .horizontal,
            ratio: 1.0,  // above maximum of 0.9
            first: .leaf(id: idA),
            second: .leaf(id: idB)
        )

        XCTAssertLessThanOrEqual(data.ratio, 0.9,
                                  "Ratio should be clamped to at most 0.9")
    }

    func test_should_accept_ratio_within_valid_range() {
        let idA = UUID()
        let idB = UUID()

        let data = SplitData(
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(id: idA),
            second: .leaf(id: idB)
        )

        XCTAssertEqual(data.ratio, 0.5, accuracy: 0.001,
                       "Ratio within range should be unchanged")
    }

    func test_should_clamp_ratio_at_boundary_values() {
        let idA = UUID()
        let idB = UUID()

        let dataMin = SplitData(
            direction: .horizontal,
            ratio: 0.1,
            first: .leaf(id: idA),
            second: .leaf(id: idB)
        )
        XCTAssertEqual(dataMin.ratio, 0.1, accuracy: 0.001,
                       "Ratio of exactly 0.1 should be accepted")

        let dataMax = SplitData(
            direction: .horizontal,
            ratio: 0.9,
            first: .leaf(id: idA),
            second: .leaf(id: idB)
        )
        XCTAssertEqual(dataMax.ratio, 0.9, accuracy: 0.001,
                       "Ratio of exactly 0.9 should be accepted")
    }

    // ==================== 8. Nested Splits ====================

    func test_should_insert_into_already_split_tree() {
        // Arrange — start with A | B, then split B into B | C
        let (tree, idA) = makeSingleLeafTree()
        let (tree2, idB) = tree.insert(at: idA, direction: .horizontal)

        // Act — insert at idB (which is inside a split)
        let (tree3, idC) = tree2.insert(at: idB, direction: .vertical)

        // Assert — should have 3 leaves total
        let allIDs = tree3.allLeafIDs()
        XCTAssertEqual(allIDs.count, 3, "Tree should have 3 leaves after nested insert")
        XCTAssertTrue(allIDs.contains(idA), "Original leaf A should still exist")
        XCTAssertTrue(allIDs.contains(idB), "Leaf B should still exist")
        XCTAssertTrue(allIDs.contains(idC), "New leaf C should exist")
    }

    func test_should_create_correct_nesting_structure_when_inserting_into_split() {
        let (tree, idA) = makeSingleLeafTree()
        let (tree2, idB) = tree.insert(at: idA, direction: .horizontal)
        let (tree3, idC) = tree2.insert(at: idB, direction: .vertical)

        // Root should be a horizontal split: A | (B / C)
        guard case .split(let outerData) = tree3.root else {
            XCTFail("Root should be a split")
            return
        }
        XCTAssertEqual(outerData.direction, .horizontal)

        // First child should be leaf A
        guard case .leaf(let firstID) = outerData.first else {
            XCTFail("First child should be a leaf")
            return
        }
        XCTAssertEqual(firstID, idA)

        // Second child should be a vertical split of B and C
        guard case .split(let innerData) = outerData.second else {
            XCTFail("Second child should be a nested split")
            return
        }
        XCTAssertEqual(innerData.direction, .vertical)

        guard case .leaf(let innerFirstID) = innerData.first,
              case .leaf(let innerSecondID) = innerData.second else {
            XCTFail("Inner split children should both be leaves")
            return
        }
        XCTAssertEqual(innerFirstID, idB, "Inner first child should be the original leaf B")
        XCTAssertEqual(innerSecondID, idC, "Inner second child should be the new leaf C")
    }

    func test_should_remove_leaf_from_deeply_nested_tree() {
        // Build: A | (B / C), then remove C, should collapse inner split
        let (tree, idA) = makeSingleLeafTree()
        let (tree2, idB) = tree.insert(at: idA, direction: .horizontal)
        let (tree3, idC) = tree2.insert(at: idB, direction: .vertical)

        // Act — remove C from the nested split
        let (result, focusTarget) = tree3.remove(idC)

        // Assert — inner split should collapse; tree becomes A | B
        let allIDs = result.allLeafIDs()
        XCTAssertEqual(allIDs.count, 2, "Should have 2 leaves after removing from nested split")
        XCTAssertTrue(allIDs.contains(idA))
        XCTAssertTrue(allIDs.contains(idB))
        XCTAssertFalse(allIDs.contains(idC), "Removed leaf should no longer appear")
        XCTAssertEqual(focusTarget, idB, "Focus should move to sibling B")
    }

    // ==================== 9. allLeafIDs ====================

    func test_should_return_single_id_for_single_leaf_tree() {
        let (tree, id) = makeSingleLeafTree()

        let ids = tree.allLeafIDs()

        XCTAssertEqual(ids, [id], "Single leaf tree should return one ID")
    }

    func test_should_return_all_ids_in_left_to_right_order() {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()

        let innerSplit = SplitNode.split(SplitData(
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(id: idB),
            second: .leaf(id: idC)
        ))
        let root = SplitNode.split(SplitData(
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(id: idA),
            second: innerSplit
        ))
        let tree = SplitTree(root: root, focusedLeafID: idA)

        let ids = tree.allLeafIDs()

        XCTAssertEqual(ids, [idA, idB, idC],
                       "allLeafIDs should return IDs in left-to-right (depth-first) order")
    }

    func test_should_return_empty_array_when_root_is_nil() {
        let tree = SplitTree(root: nil, focusedLeafID: nil)

        let ids = tree.allLeafIDs()

        XCTAssertTrue(ids.isEmpty, "allLeafIDs should return empty array for nil root")
    }

    // ==================== findParentSplit ====================

    func test_should_find_parent_split_of_nested_leaf() {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()

        let innerSplit = SplitData(
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(id: idB),
            second: .leaf(id: idC)
        )
        let root = SplitNode.split(SplitData(
            direction: .vertical,
            ratio: 0.5,
            first: .leaf(id: idA),
            second: .split(innerSplit)
        ))
        let tree = SplitTree(root: root, focusedLeafID: idA)

        let parent = tree.findParentSplit(of: idB)

        XCTAssertEqual(parent, innerSplit,
                       "Parent of idB should be the inner horizontal split")
    }

    func test_should_return_nil_parent_for_root_leaf() {
        let (tree, rootID) = makeSingleLeafTree()

        let parent = tree.findParentSplit(of: rootID)

        XCTAssertNil(parent, "Root leaf has no parent split")
    }

    // ==================== Resize ====================

    func test_should_adjust_ratio_when_resizing() {
        let (tree, idA) = makeSingleLeafTree()
        let (splitTree, _) = tree.insert(at: idA, direction: .horizontal)

        let resized = splitTree.resize(
            node: idA,
            by: 50.0,
            direction: .horizontal,
            bounds: CGSize(width: 800, height: 600),
            minSize: 100.0
        )

        guard case .split(let data) = resized.root else {
            XCTFail("Root should remain a split after resize")
            return
        }

        // Ratio should have changed from the default 0.5
        XCTAssertNotEqual(data.ratio, 0.5, "Ratio should change after resize")
        XCTAssertGreaterThanOrEqual(data.ratio, 0.1, "Ratio must stay within bounds")
        XCTAssertLessThanOrEqual(data.ratio, 0.9, "Ratio must stay within bounds")
    }

    func test_should_not_resize_below_min_size() {
        let (tree, idA) = makeSingleLeafTree()
        let (splitTree, _) = tree.insert(at: idA, direction: .horizontal)

        // Try to resize by an extreme amount that would violate minSize
        let resized = splitTree.resize(
            node: idA,
            by: -10000.0,
            direction: .horizontal,
            bounds: CGSize(width: 800, height: 600),
            minSize: 100.0
        )

        guard case .split(let data) = resized.root else {
            XCTFail("Root should remain a split after resize")
            return
        }

        // The ratio should be clamped so that neither pane is below minSize
        XCTAssertGreaterThanOrEqual(data.ratio, 0.1,
                                     "Ratio must be clamped to keep panes above min size")
    }
}
