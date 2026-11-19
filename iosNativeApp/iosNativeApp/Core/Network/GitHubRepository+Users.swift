import Foundation

extension GitHubRepository {
    func viewerProfile() async throws -> ViewerProfile {
        let data = try await client.graphQL("""
            query {
              viewer {
                login name avatarUrl bio company location url
                followers { totalCount }
                following { totalCount }
                repositories(ownerAffiliations: OWNER) { totalCount }
              }
            }
            """)
        guard let v = data["viewer"] else {
            throw GitHubAPIError(statusCode: 500, message: "Missing viewer in GraphQL response", isSynthetic: true)
        }
        return ViewerProfile(
            login: v["login"]?.string ?? "",
            name: v["name"]?.string,
            avatarURL: v["avatarUrl"]?.string ?? "",
            bio: v["bio"]?.string,
            company: v["company"]?.string,
            location: v["location"]?.string,
            followersCount: v["followers"]?["totalCount"]?.int ?? 0,
            followingCount: v["following"]?["totalCount"]?.int ?? 0,
            publicReposCount: v["repositories"]?["totalCount"]?.int ?? 0,
            htmlURL: v["url"]?.string ?? ""
        )
    }

    func userProfile(_ login: String) async throws -> UserProfile {
        let clean = login.trimmingCharacters(in: .whitespaces)
        let json = try await client.json(.get, "users/\(APIPath.seg(clean))", failure: String(localized: "Failed to load user @\(clean)"))
        let isOrg = json["type"]?.string?.caseInsensitiveCompare("Organization") == .orderedSame
        let resolvedLogin = json["login"]?.string ?? clean
        let following = isOrg ? false : ((try? await isFollowing(resolvedLogin)) ?? false)
        func nonEmpty(_ key: String) -> String? { json[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }
        return UserProfile(
            login: resolvedLogin,
            name: nonEmpty("name"),
            avatarURL: json["avatar_url"]?.string ?? "",
            bio: nonEmpty("bio"),
            company: nonEmpty("company"),
            location: nonEmpty("location"),
            blogURL: nonEmpty("blog"),
            twitterUsername: nonEmpty("twitter_username"),
            email: nonEmpty("email"),
            followersCount: json["followers"]?.int ?? 0,
            followingCount: json["following"]?.int ?? 0,
            publicReposCount: json["public_repos"]?.int ?? 0,
            publicGistsCount: json["public_gists"]?.int ?? 0,
            isOrganization: isOrg,
            viewerIsFollowing: following,
            createdAt: json["created_at"]?.string ?? "",
            htmlURL: json["html_url"]?.string ?? ""
        )
    }

    func isFollowing(_ login: String) async throws -> Bool {
        let (_, response) = try await client.send(.get, "user/following/\(APIPath.seg(login))")
        return response.statusCode == 204
    }

    func setFollowing(_ login: String, follow: Bool) async throws {
        let (data, response) = try await client.send(follow ? .put : .delete, "user/following/\(APIPath.seg(login))")
        if response.statusCode == 404 {
            throw GitHubAPIError(statusCode: 404, message: String(localized: "Couldn't update follow state for @\(login). Your token may lack the 'user:follow' scope; sign out and sign in again."))
        }
        try GitHubHttpClient.ensureSuccess(response, data: data, failure: String(localized: "Failed to update follow state"))
    }

    func followers(_ login: String) async throws -> [UserSummary] {
        try await userList("users/\(APIPath.seg(login))/followers")
    }

    func following(_ login: String) async throws -> [UserSummary] {
        try await userList("users/\(APIPath.seg(login))/following")
    }

    func organizations(_ login: String) async throws -> [OrganizationSummary] {
        let json = try await client.json(.get, "users/\(APIPath.seg(login))/orgs", failure: String(localized: "Failed to load organizations"))
        return json.items.compactMap { obj in
            guard let login = obj["login"]?.string else { return nil }
            return OrganizationSummary(login: login, avatarURL: obj["avatar_url"]?.string ?? "", description: obj["description"]?.string)
        }
    }

    func contributionCalendar(_ login: String) async throws -> ContributionCalendar {
        let data = try await client.graphQL("""
            query($login: String!) {
              user(login: $login) {
                contributionsCollection {
                  contributionCalendar {
                    totalContributions
                    weeks { contributionDays { date contributionCount contributionLevel } }
                  }
                }
              }
            }
            """, variables: ["login": .string(login)])
        guard let calendar = data["user"]?["contributionsCollection"]?["contributionCalendar"] else {
            throw GitHubAPIError(statusCode: 404, message: "Contribution calendar not found for @\(login)", isSynthetic: true)
        }
        let weeks = (calendar["weeks"]?.items ?? []).map { week in
            ContributionWeek(days: (week["contributionDays"]?.items ?? []).compactMap { day in
                guard let date = day["date"]?.string else { return nil }
                let level = switch day["contributionLevel"]?.string?.uppercased() {
                case "FIRST_QUARTILE": 1
                case "SECOND_QUARTILE": 2
                case "THIRD_QUARTILE": 3
                case "FOURTH_QUARTILE": 4
                default: 0
                }
                return ContributionDay(date: date, count: day["contributionCount"]?.int ?? 0, level: level)
            })
        }
        return ContributionCalendar(totalContributions: calendar["totalContributions"]?.int ?? 0, weeks: weeks)
    }

    private func userList(_ path: String) async throws -> [UserSummary] {
        let json = try await client.json(.get, path, query: ["per_page": "50"], failure: String(localized: "Failed to load users"))
        return json.items.map { Self.parseUser($0) }
    }
}
