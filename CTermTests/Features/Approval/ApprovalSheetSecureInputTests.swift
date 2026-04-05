// ApprovalSheetSecureInputTests.swift
// CTerm
//
// Data-flow tests for the MP1 secure-input approval path. We do NOT render
// the view — these tests exercise the pure data types and the Approve-enabled
// invariant exposed by ApprovalSheet.canSubmit.

import Foundation
import Testing
@testable import CTerm

@MainActor
@Suite("Approval Sheet — Secure Input")
struct ApprovalSheetSecureInputTests {

    @Test("ApprovalContext defaults secureInputRequest to nil (back-compat)")
    func defaultSecureInputRequestIsNil() {
        let context = ApprovalContext(
            stepID: nil,
            riskScore: 20,
            riskTier: .low,
            action: ActionDescriptor(
                what: "Run: ls",
                why: "Inspect repo",
                impact: "Read-only",
                rollback: nil
            )
        )
        #expect(context.secureInputRequest == nil)
    }

    @Test("ApprovalContext carries a populated secureInputRequest when supplied")
    func secureInputRequestRoundTrips() {
        let req = ApprovalSecureInputRequest(
            fieldLabel: "Password",
            placeholder: "Enter password for sudo",
            matchedLine: "[sudo] password for chris:"
        )
        let context = ApprovalContext(
            stepID: nil,
            riskScore: 55,
            riskTier: .high,
            action: ActionDescriptor(
                what: "Respond to 'Password / passphrase'",
                why: "Waiting for input",
                impact: "Sends text to terminal",
                rollback: nil
            ),
            secureInputRequest: req
        )
        #expect(context.secureInputRequest?.fieldLabel == "Password")
        #expect(context.secureInputRequest?.matchedLine == "[sudo] password for chris:")
        #expect(context.secureInputRequest?.placeholder == "Enter password for sudo")
    }

    @Test("ApprovalPresenter forwards enteredSecureText through resume callback")
    func presenterForwardsEnteredSecureText() {
        let presenter = ApprovalPresenter.shared
        let session = AgentSession(
            intent: "Run sudo command",
            rawPrompt: "Run sudo command",
            tabID: nil,
            kind: .multiStep,
            backend: .ollama
        )
        let secureReq = ApprovalSecureInputRequest(
            fieldLabel: "Password",
            placeholder: "Enter password",
            matchedLine: "[sudo] password for chris:"
        )
        let context = ApprovalContext(
            stepID: nil,
            riskScore: 55,
            riskTier: .high,
            action: ActionDescriptor(
                what: "Respond to password prompt",
                why: "Command waiting",
                impact: "Sends to terminal",
                rollback: nil
            ),
            secureInputRequest: secureReq
        )

        var resolvedAnswer: ApprovalAnswer?
        var resolvedText: String?
        session.onApprovalResolved = { answer, text in
            resolvedAnswer = answer
            resolvedText = text
        }

        presenter.setRepoPath(nil)
        presenter.session(session, didRequestApproval: context)
        presenter.resolve(answer: .approved, scope: .once, enteredSecureText: "hunter2")

        #expect(resolvedAnswer == .approved)
        #expect(resolvedText == "hunter2")
    }

    @Test("ApprovalPresenter forwards nil entered text for non-secure approvals")
    func presenterForwardsNilWhenNoSecureInput() {
        let presenter = ApprovalPresenter.shared
        let session = AgentSession(
            intent: "Run ls",
            rawPrompt: "Run ls",
            tabID: nil,
            kind: .multiStep,
            backend: .ollama
        )
        let context = ApprovalContext(
            stepID: nil,
            riskScore: 15,
            riskTier: .low,
            action: ActionDescriptor(
                what: "Run: ls",
                why: "Inspect",
                impact: "Read-only",
                rollback: nil
            )
        )

        var resolvedText: String? = "not-nil-sentinel"
        var callbackFired = false
        session.onApprovalResolved = { _, text in
            callbackFired = true
            resolvedText = text
        }

        presenter.setRepoPath(nil)
        presenter.session(session, didRequestApproval: context)
        presenter.resolve(answer: .approved, scope: .once)

        #expect(callbackFired)
        #expect(resolvedText == nil)
    }

    // MARK: - canSubmit invariant

    @Test("canSubmit is true when there is no secure input request")
    func canSubmitTrueWithoutSecureRequest() {
        #expect(ApprovalSheet.canSubmit(secureInputRequest: nil, enteredText: "") == true)
        #expect(ApprovalSheet.canSubmit(secureInputRequest: nil, enteredText: "anything") == true)
    }

    @Test("canSubmit is false when secure input is required but text is empty")
    func canSubmitFalseWhenEmpty() {
        let req = ApprovalSecureInputRequest(
            fieldLabel: "Password",
            placeholder: "Enter password",
            matchedLine: "Password:"
        )
        #expect(ApprovalSheet.canSubmit(secureInputRequest: req, enteredText: "") == false)
    }

    @Test("canSubmit is true when secure input is required and text is non-empty")
    func canSubmitTrueWhenNonEmpty() {
        let req = ApprovalSecureInputRequest(
            fieldLabel: "Password",
            placeholder: "Enter password",
            matchedLine: "Password:"
        )
        #expect(ApprovalSheet.canSubmit(secureInputRequest: req, enteredText: "x") == true)
        #expect(ApprovalSheet.canSubmit(secureInputRequest: req, enteredText: "hunter2") == true)
    }
}
