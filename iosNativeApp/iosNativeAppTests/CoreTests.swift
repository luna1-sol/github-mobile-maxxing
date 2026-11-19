import Foundation
import Testing
@testable import iosNativeApp

/// Mirrors core/network DiffParserTest.kt.
struct DiffParserTests {
    @Test func parsesHunksWithLineNumbers() throws {
        let patch = """
            @@ -1,3 +1,4 @@ fun main()
             context
            -removed
            +added one
            +added two
             tail
            \\ No newline at end of file
            """
        let hunks = DiffParser.parse(patch)
        let hunk = try #require(hunks.first)
        #expect(hunks.count == 1)
        #expect(hunk.oldStart == 1 && hunk.oldCount == 3 && hunk.newStart == 1 && hunk.newCount == 4)
        #expect(hunk.lines.map(\.kind) == [.context, .removed, .added, .added, .context, .meta])
        #expect(hunk.lines[0].oldLineNumber == 1 && hunk.lines[0].newLineNumber == 1)
        #expect(hunk.lines[1].oldLineNumber == 2 && hunk.lines[1].newLineNumber == nil)
        #expect(hunk.lines[2].newLineNumber == 2 && hunk.lines[3].newLineNumber == 3)
        #expect(hunk.lines[4].oldLineNumber == 3 && hunk.lines[4].newLineNumber == 4)
        #expect(hunk.lines[2].content == "added one")
    }

    @Test func missingCountsDefaultToOne() throws {
        let header = try #require(DiffParser.parseHunkHeader("@@ -5 +7 @@"))
        #expect(header == (5, 1, 7, 1))
    }

    @Test func multipleHunks() {
        let patch = "@@ -1,1 +1,1 @@\n-a\n+b\n@@ -10,2 +10,2 @@\n x\n-y\n+z"
        let hunks = DiffParser.parse(patch)
        #expect(hunks.count == 2)
        #expect(hunks[1].lines.first?.oldLineNumber == 10)
    }

    @Test func emptyPatchHasNoHunks() {
        #expect(DiffParser.parse(nil).isEmpty)
        #expect(DiffParser.parse("  \n").isEmpty)
        #expect(DiffParser.parse("no header here").isEmpty)
    }
}

/// Mirrors core/auth DeviceFlowClientTest.kt.
struct DeviceFlowClientTests {
    @Test(arguments: [
        "https://github.com/login/device",
        "https://github.com/login/device/",
        "https://github.com/login/device?user_code=ABCD-EFGH",
    ])
    func trustsGitHubDevicePage(uri: String) {
        #expect(DeviceFlowClient.isTrustedVerificationURI(uri))
    }

    @Test(arguments: [
        "http://github.com/login/device",
        "https://evil.example/login/device",
        "https://github.com/login/device-evil",
        "https://github.com/login/device/../../phish",
        "https://github.com:8443/login/device",
        "https://user@github.com/login/device",
        "javascript:alert(1)",
    ])
    func rejectsOtherURIs(uri: String) {
        #expect(!DeviceFlowClient.isTrustedVerificationURI(uri))
    }

    @Test func formEncodingEscapesReservedAndNonASCII() {
        let encoded = DeviceFlowClient.formEncode(["scope": "repo read:user", "client_id": "Ov23li", "x": "a&b=c/é"])
        #expect(encoded == "client_id=Ov23li&scope=repo%20read%3Auser&x=a%26b%3Dc%2F%C3%A9")
    }
}

struct JSONValueTests {
    @Test func decodesNestedValues() throws {
        let json = try JSONValue.parse(Data(#"{"a":{"b":[1,"x",true,null]},"n":12,"s":"t","nul":null}"#.utf8))
        #expect(json["a"]?["b"]?[0]?.int == 1)
        #expect(json["a"]?["b"]?[1]?.string == "x")
        #expect(json["a"]?["b"]?[2]?.bool == true)
        #expect(json["n"]?.int == 12)
        #expect(json["s"]?.string == "t")
        // Explicit nulls read as missing, like kotlinx `explicitNulls = false`.
        #expect(json["nul"] == nil)
        #expect(json["missing"]?.items.isEmpty ?? true)
    }

    @Test func encodesGraphQLVariables() throws {
        let body: JSONValue = ["query": "q", "variables": ["number": .number(42)]]
        let text = String(decoding: try body.encoded(), as: UTF8.self)
        #expect(text.contains(#""number":42"#))
    }
}

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

struct NotificationParsingTests {
    @Test func parsesRestNotification() throws {
        let json = try JSONValue.parse(Data("""
            {"id":"123","unread":true,"reason":"review_requested","updated_at":"2026-01-02T03:04:05Z",
             "subject":{"title":"Fix","type":"PullRequest","url":"https://api.github.com/repos/o/r/pulls/9","latest_comment_url":null},
             "repository":{"full_name":"o/r","name":"r","private":true,"owner":{"login":"o","avatar_url":"https://a"}}}
            """.utf8))
        let thread = try #require(GitHubRepository.parseNotification(json))
        #expect(thread.reason == .reviewRequested)
        #expect(thread.subjectType == .pullRequest)
        #expect(thread.issueRef == IssueRef(owner: "o", repo: "r", number: 9))
        #expect(thread.htmlFallbackURL.absoluteString == "https://github.com/o/r/pull/9")
        #expect(thread.isPrivate)
    }

    @Test func checkSuiteFallsBackToActions() {
        let thread = NotificationThread(id: "1", unread: false, reason: .ciActivity, updatedAt: "", subjectTitle: "CI",
                                        subjectType: .checkSuite, subjectURL: nil, latestCommentURL: nil,
                                        repoFullName: "o/r", repoOwner: "o", repoName: "r")
        #expect(thread.issueRef == nil)
        #expect(thread.htmlFallbackURL.absoluteString == "https://github.com/o/r/actions")
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
