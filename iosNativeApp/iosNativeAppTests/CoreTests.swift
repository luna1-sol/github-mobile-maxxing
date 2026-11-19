import Foundation
import Testing
@testable import iosNativeApp

/// Mirrors core/network RepoPermissionsGatingTest.kt.
struct RepoCapabilitiesTests {
    private func repo(permission: String?, known: Bool, owner: String = "octo", archived: Bool = false) -> RepoSummary {
        RepoSummary(id: "1", name: "r", owner: owner, fullName: "\(owner)/r", viewerPermission: permission,
                    hasKnownPermission: known, isArchived: archived)
    }

    @Test func writePermissionAllowsPush() {
        let caps = RepoCapabilities.resolve(repo(permission: "WRITE", known: true), viewerLogin: "someone")
        #expect(caps.canPush && caps.canTriage)
    }

    @Test func readPermissionDeniesPush() {
        let caps = RepoCapabilities.resolve(repo(permission: "READ", known: true), viewerLogin: "octo")
        #expect(!caps.canPush && !caps.canTriage)
    }

    @Test func unknownPermissionFallsBackToOwnership() {
        #expect(RepoCapabilities.resolve(repo(permission: nil, known: false), viewerLogin: "OCTO").canPush)
        #expect(!RepoCapabilities.resolve(repo(permission: nil, known: false), viewerLogin: "other").canPush)
    }

    @Test func archivedRepositoriesAreReadOnly() {
        let caps = RepoCapabilities.resolve(repo(permission: "ADMIN", known: true, archived: true), viewerLogin: "octo")
        #expect(!caps.canPush && !caps.canCreateIssue && !caps.canComment)
    }
}

struct MarkdownParserTests {
    @Test func parsesBlocks() {
        let blocks = MarkdownParser.parse("""
            # Title

            Some *text*
            continued.

            - [x] done
            - todo

            ```swift
            let x = 1
            ```

            > quote

            | a | b |
            |---|---|
            | 1 | 2 |

            ---
            """)
        #expect(blocks.count == 7)
        #expect(blocks[0] == .heading(level: 1, text: "Title"))
        #expect(blocks[1] == .paragraph("Some *text*\ncontinued."))
        if case .list(let items) = blocks[2] {
            #expect(items.map(\.checked) == [true, nil])
        } else {
            Issue.record("expected a list")
        }
        #expect(blocks[3] == .code(language: "swift", text: "let x = 1"))
        #expect(blocks[5] == .table(header: ["a", "b"], rows: [["1", "2"]]))
        #expect(blocks[6] == .rule)
    }

    @Test func extractsImagesFromHTMLAndBadges() {
        let blocks = MarkdownParser.parse(#"<p align="center"><img src="logo.png" width="80"></p>"# + "\n\n[![CI](https://ci/badge.svg)](https://ci)")
        #expect(blocks.contains(.image(url: "logo.png", alt: "")))
        #expect(blocks.contains(.image(url: "https://ci/badge.svg", alt: "CI")))
    }

    @Test func resolvesRelativeLinksAgainstTheRepository() {
        let context = MarkdownContext(repo: RepoRef(owner: "o", name: "r"), ref: "main", directory: "docs")
        #expect(context.resolveImage("img/a.png")?.absoluteString == "https://raw.githubusercontent.com/o/r/main/docs/img/a.png")
        #expect(context.resolveLink("../README.md")?.absoluteString == "https://github.com/o/r/blob/main/README.md")
        #expect(context.resolveImage("https://github.com/o/r/blob/main/x.png")?.absoluteString == "https://raw.githubusercontent.com/o/r/main/x.png")
        #expect(context.resolveLink("#section") == nil)
    }
}

/// Mirrors the summary strings produced by core/network `GitHubRestService.parseActivityEvent`.
struct ActivitySummaryTests {
    @Test func unrecognizedSummariesPassThrough() {
        #expect(ActivitySummary.localized(kind: .member, summary: "added a member", number: nil, branch: nil, releaseTag: nil)
                == "added a member")
        #expect(ActivitySummary.localized(kind: .push, summary: "something else", number: nil, branch: nil, releaseTag: nil)
                == "something else")
    }

    @Test func pullRequestAndIssueVerbsAreRecognized() {
        let merged = ActivitySummary.localized(kind: .pullRequest, summary: "merged pull request #12", number: 12, branch: nil, releaseTag: nil)
        #expect(merged == String(localized: "merged pull request \("#12")"))
        let closed = ActivitySummary.localized(kind: .issues, summary: "closed issue #3", number: 3, branch: nil, releaseTag: nil)
        #expect(closed == String(localized: "closed issue \("#3")"))
    }

    @Test func pushUsesBranchAndCount() {
        let text = ActivitySummary.localized(kind: .push, summary: "pushed 2 commits to main", number: nil, branch: "main", releaseTag: nil)
        #expect(text == String(localized: "pushed \(2) commit(s) to \("main")"))
    }

    @Test func threadCommentsWithoutNumber() {
        let text = ActivitySummary.localized(kind: .issueComment, summary: "commented on thread", number: nil, branch: nil, releaseTag: nil)
        #expect(text == String(localized: "commented on a thread"))
    }
}
