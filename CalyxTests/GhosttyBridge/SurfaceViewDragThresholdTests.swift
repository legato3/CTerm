// SurfaceViewDragThresholdTests.swift
// CalyxTests
//
// Tests for SurfaceView.isDragBeyondThreshold static helper.
// Verifies drag threshold logic for click vs drag discrimination.

import Testing
@testable import Calyx
import AppKit

@MainActor
@Suite("SurfaceView Drag Threshold Tests")
struct SurfaceViewDragThresholdTests {

    @Test("Drag threshold constant is 3 points")
    func thresholdValue() {
        #expect(SurfaceView.dragThreshold == 3)
    }

    @Test("Zero movement is below threshold")
    func zeroMovement() {
        let start = NSPoint(x: 100, y: 100)
        #expect(!SurfaceView.isDragBeyondThreshold(from: start, to: start))
    }

    @Test("Sub-pixel movement is below threshold")
    func subPixelMovement() {
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 100.5, y: 100.5)
        #expect(!SurfaceView.isDragBeyondThreshold(from: start, to: end))
    }

    @Test("Movement of 2pt is below threshold")
    func twoPointMovement() {
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 102, y: 100)
        #expect(!SurfaceView.isDragBeyondThreshold(from: start, to: end))
    }

    @Test("Movement of exactly 3pt meets threshold")
    func exactThreshold() {
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 103, y: 100)
        #expect(SurfaceView.isDragBeyondThreshold(from: start, to: end))
    }

    @Test("Diagonal movement beyond threshold")
    func diagonalBeyond() {
        let start = NSPoint(x: 0, y: 0)
        // distance = sqrt(2.5^2 + 2.5^2) = sqrt(12.5) ≈ 3.54 > 3
        let end = NSPoint(x: 2.5, y: 2.5)
        #expect(SurfaceView.isDragBeyondThreshold(from: start, to: end))
    }

    @Test("Diagonal movement below threshold")
    func diagonalBelow() {
        let start = NSPoint(x: 0, y: 0)
        // distance = sqrt(1^2 + 1^2) = sqrt(2) ≈ 1.41 < 3
        let end = NSPoint(x: 1, y: 1)
        #expect(!SurfaceView.isDragBeyondThreshold(from: start, to: end))
    }

    @Test("Negative direction movement works")
    func negativeDirection() {
        let start = NSPoint(x: 100, y: 100)
        let end = NSPoint(x: 96, y: 100)  // -4pt, distance = 4 > 3
        #expect(SurfaceView.isDragBeyondThreshold(from: start, to: end))
    }

    @Test("Custom threshold parameter works")
    func customThreshold() {
        let start = NSPoint(x: 0, y: 0)
        let end = NSPoint(x: 5, y: 0)
        #expect(!SurfaceView.isDragBeyondThreshold(from: start, to: end, threshold: 10))
        #expect(SurfaceView.isDragBeyondThreshold(from: start, to: end, threshold: 3))
    }
}
