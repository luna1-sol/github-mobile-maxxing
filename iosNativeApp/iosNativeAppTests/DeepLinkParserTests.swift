import Foundation
import Testing
@testable import iosNativeApp

/// Mirrors composeApp/src/commonTest/.../DeepLinkParserTest.kt and GitHubUrlParserTest.kt.
struct DeepLinkParserTests {
    @Test(arguments: [
        ("githubmaxxing-native://thread/octocat/hello-world/123", IssueRef(owner: "octocat", repo: "hello-world", number: 123)),
        ("githubmaxxing-native://thread/o/r/5?x=1#f", IssueRef(owner: "o", repo: "r", number: 5)),
        ("githubmaxxing-native://thread/octo/%E3%83%AA/2", IssueRef(owner: "octo", repo: "リ", number: 2)),
        ("githubmaxxing-native://thread/o/r/12/", IssueRef(owner: "o", repo: "r", number: 12)),
        ("GitHubMaxxing-Native://THREAD/Octo/Repo/7", IssueRef(owner: "Octo", repo: "Repo", number: 7)),
        ("githubmaxxing-native://thread/o/r/%34%32", IssueRef(owner: "o", repo: "r", number: 42)),
    ])
    func acceptsCanonicalLinks(url: String, expected: IssueRef) {
        #expect(DeepLinkParser.parseStrict(url) == expected)
    }

    @Test(arguments: [
        "githubmaxxing-native://thread/o/r/1/extra",
        "githubmaxxing-native://thread/o/r/1/2",
        "githubmaxxing-native://thread//o//r/1//",
        "githubmaxxing-native://thread//r/1",
        "githubmaxxing-native://thread/o//1",
        "githubmaxxing-native://thread/o/r/0",
        "githubmaxxing-native://thread/o/r/-1",
        "githubmaxxing-native://thread/o/r/+1",
        "githubmaxxing-native://thread:8080/o/r/1",
        "githubmaxxing-native://user@thread/o/r/1",
        "  githubmaxxing-native://thread/o/r/3  ",
        "githubmaxxing-native://thread/o/r%ZZ/1",
        "githubmaxxing-native://thread/o/100%/1",
        "githubmaxxing-native://thread/o%2Fr/r/1",
        "githubmaxxing-native://thread/o/r/%E3%81",
        "githubmaxxing-native://thread/%20/r/1",
        "", "   ", "https://thread/o/r/1", "githubmaxxing-native:/thread/o/r/1",
        "githubmaxxing-native://other/o/r/1", "githubmaxxing-native:///o/r/1", "githubmaxxing-native://thread",
        "githubmaxxing-native://thread/o/r", "githubmaxxing-native://thread/o/r/", "githubmaxxing-native://thread/o/r/abc",
        "githubmaxxing-native://thread/o/r/1.5", "githubmaxxing-native://thread/o/r/999999999999999999",
        "githubmaxxing-native://thread/o/r/1//", "not a url",
        "githubmaxxing://thread/o/r/1",
    ])
    func rejectsLooseOrMalformedLinks(url: String) {
        #expect(DeepLinkParser.parseStrict(url) == nil)
    }

    @Test func rejectsNil() {
        #expect(DeepLinkParser.parseStrict(nil) == nil)
    }

    @Test func buildsThreadURLOnlyForPositiveNumbers() {
        #expect(DeepLinkParser.threadURL(owner: "octo", repo: "repo", number: 42) == "githubmaxxing-native://thread/octo/repo/42")
        #expect(DeepLinkParser.threadURL(owner: "octo", repo: "repo", number: nil) == nil)
        #expect(DeepLinkParser.threadURL(owner: "octo", repo: "repo", number: 0) == nil)
        #expect(DeepLinkParser.threadURL(owner: "octo", repo: "repo", number: -3) == nil)
        #expect(DeepLinkParser.threadURL(owner: "", repo: "repo", number: 1) == nil)
        #expect(DeepLinkParser.threadURL(owner: "octo", repo: "  ", number: 1) == nil)
        #expect(DeepLinkParser.threadURL(owner: "oc/to", repo: "repo", number: 1) == nil)
    }

    @Test func builtURLRoundTrips() throws {
        let url = try #require(DeepLinkParser.threadURL(owner: "octo", repo: "リポ", number: 9))
        #expect(DeepLinkParser.parseStrict(url) == IssueRef(owner: "octo", repo: "リポ", number: 9))
    }
}

struct GitHubUrlParserTests {
    private func parse(_ string: String) -> AppDeepLink? {
        GitHubUrlParser.parse(URL(string: string)!)
    }

    @Test func parsesIssueAndPullLinks() {
        #expect(parse("https://github.com/octo/repo/issues/12") == .issueOrPull(IssueRef(owner: "octo", repo: "repo", number: 12), fromNotification: false))
        #expect(parse("https://github.com/octo/repo/pull/7/files") == .issueOrPull(IssueRef(owner: "octo", repo: "repo", number: 7), fromNotification: false))
    }

    @Test func parsesRepositoryAndUserLinks() {
        #expect(parse("https://github.com/octo/repo") == .repository(RepoRef(owner: "octo", name: "repo")))
        #expect(parse("https://www.github.com/octo/repo.git") == .repository(RepoRef(owner: "octo", name: "repo")))
        #expect(parse("https://github.com/octo/repo/tree/main/src") == .repository(RepoRef(owner: "octo", name: "repo")))
        #expect(parse("https://github.com/octocat") == .user("octocat"))
    }

    @Test func reservedPathsStayOnTheWeb() {
        let url = URL(string: "https://github.com/settings/tokens")!
        #expect(GitHubUrlParser.parse(url) == .externalWeb(url))
    }

    @Test func ignoresOtherHosts() {
        #expect(parse("https://gitlab.com/octo/repo") == nil)
        #expect(parse("mailto:octo@example.com") == nil)
    }

    @Test func notificationLinksComeFromNotifications() {
        #expect(parse("githubmaxxing-native://thread/o/r/3") == .issueOrPull(IssueRef(owner: "o", repo: "r", number: 3), fromNotification: true))
    }
}
