package dev.maxxing.github.ios

import dev.maxxing.github.auth.SessionManager
import dev.maxxing.github.model.ActivityEvent
import dev.maxxing.github.model.AppBranding
import dev.maxxing.github.model.AuthSession
import dev.maxxing.github.model.BranchRef
import dev.maxxing.github.model.CodeSearchHit
import dev.maxxing.github.model.CommitDetail
import dev.maxxing.github.model.CommitSummary
import dev.maxxing.github.model.ContributionCalendar
import dev.maxxing.github.model.DeviceCodeState
import dev.maxxing.github.model.DeviceFlowErrorKind
import dev.maxxing.github.model.FileContent
import dev.maxxing.github.model.IssueFilterPreset
import dev.maxxing.github.model.IssueOrPullDetail
import dev.maxxing.github.model.IssueOrPullSummary
import dev.maxxing.github.model.IssueStateFilter
import dev.maxxing.github.model.LabelTag
import dev.maxxing.github.model.MergeMethod
import dev.maxxing.github.model.NotificationThread
import dev.maxxing.github.model.OrganizationSummary
import dev.maxxing.github.model.PullFileChange
import dev.maxxing.github.model.RateLimitInfo
import dev.maxxing.github.model.RepoDetail
import dev.maxxing.github.model.RepoSummary
import dev.maxxing.github.model.ReviewEvent
import dev.maxxing.github.model.TreeEntry
import dev.maxxing.github.model.UserProfile
import dev.maxxing.github.model.UserSummary
import dev.maxxing.github.model.ViewerProfile
import dev.maxxing.github.network.GitHubRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

/** Handle for a running subscription; Swift calls [cancel] to stop it. */
class Cancellable internal constructor(private val job: Job) {
    fun cancel() = job.cancel()
}

/**
 * Entry point of the shared Kotlin core for the native SwiftUI app (iosNativeApp).
 *
 * It owns the same [SessionManager] and [GitHubRepository] as composeApp's AppContainer and exposes them in a
 * Swift-friendly shape: suspend functions become `async throws` in Swift (failures surface as `NSError` whose
 * `localizedDescription` is the Kotlin message), and flows are observed through callbacks delivered on the main
 * thread. No networking, auth, caching or parsing logic lives here; it only adapts the existing core API.
 */
class MaxxingCore(defaultClientId: String = AppBranding.DEFAULT_OAUTH_CLIENT_ID) {
    val sessionManager: SessionManager = SessionManager(defaultClientId = defaultClientId)
    val repository: GitHubRepository = GitHubRepository(sessionManager)

    private val scope = CoroutineScope(
        SupervisorJob() + Dispatchers.Main + CoroutineExceptionHandler { _, _ -> /* reported via callbacks */ }
    )

    // region Session

    /** Loads the stored session and preferences from the Keychain / NSUserDefaults. */
    @Throws(Exception::class)
    suspend fun initialize() = sessionManager.initialize()

    val currentSession: AuthSession? get() = sessionManager.session.value

    /** Calls [onChange] with the current session and again whenever it changes (sign-in, refresh, sign-out). */
    fun observeSession(onChange: (AuthSession?) -> Unit): Cancellable =
        Cancellable(scope.launch { sessionManager.session.collect { onChange(it) } })

    /** Runs the OAuth Device Flow for [clientId]; the session is stored when it reaches `Authenticated`. */
    fun startDeviceFlow(clientId: String, onState: (DeviceCodeState) -> Unit): Cancellable =
        Cancellable(
            scope.launch {
                sessionManager.startDeviceFlow(clientId)
                    .catch { error ->
                        if (error is CancellationException) throw error
                        emit(DeviceCodeState.Error(error.message ?: "Device flow failed", kind = DeviceFlowErrorKind.OTHER))
                    }
                    .collect { onState(it) }
            }
        )

    @Throws(Exception::class)
    suspend fun signInWithPat(token: String): AuthSession = sessionManager.signInWithPat(token).getOrThrow()

    @Throws(Exception::class)
    suspend fun signOut() {
        sessionManager.signOut()
        repository.clearCache()
    }

    val rateLimit: RateLimitInfo get() = repository.rateLimit.value

    // endregion

    // region Users & activity

    @Throws(Exception::class)
    suspend fun viewerProfile(forceRefresh: Boolean): ViewerProfile = repository.getViewerProfile(forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun userProfile(login: String, forceRefresh: Boolean): UserProfile =
        repository.getUserProfile(login, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun setFollowing(login: String, follow: Boolean) = repository.setFollowingUser(login, follow).getOrThrow()

    @Throws(Exception::class)
    suspend fun userRepositories(login: String, isOrganization: Boolean, forceRefresh: Boolean): List<RepoSummary> =
        repository.getUserRepositories(login, isOrganization, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun organizations(login: String, forceRefresh: Boolean): List<OrganizationSummary> =
        repository.getUserOrganizations(login, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun followers(login: String, forceRefresh: Boolean): List<UserSummary> =
        repository.getUserFollowers(login, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun following(login: String, forceRefresh: Boolean): List<UserSummary> =
        repository.getUserFollowing(login, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun contributionCalendar(login: String, forceRefresh: Boolean): ContributionCalendar =
        repository.getContributionCalendar(login, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun receivedEvents(login: String, forceRefresh: Boolean): List<ActivityEvent> =
        repository.getReceivedEvents(login, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun userEvents(login: String, forceRefresh: Boolean): List<ActivityEvent> =
        repository.getUserEvents(login, forceRefresh).getOrThrow()

    // endregion

    // region Notifications

    @Throws(Exception::class)
    suspend fun notifications(all: Boolean, participating: Boolean): List<NotificationThread> =
        repository.getNotifications(all = all, participating = participating, page = 1, forceRefresh = true).getOrThrow()

    @Throws(Exception::class)
    suspend fun markNotificationRead(threadId: String) = repository.markNotificationRead(threadId).getOrThrow()

    @Throws(Exception::class)
    suspend fun markNotificationDone(threadId: String) = repository.markNotificationDone(threadId).getOrThrow()

    @Throws(Exception::class)
    suspend fun markAllNotificationsRead() = repository.markAllNotificationsRead().getOrThrow()

    // endregion

    // region Issues & pull requests

    @Throws(Exception::class)
    suspend fun myIssuesAndPulls(
        preset: IssueFilterPreset,
        viewerLogin: String,
        state: IssueStateFilter,
        forceRefresh: Boolean,
    ): List<IssueOrPullSummary> = repository.getMyIssuesAndPulls(preset, viewerLogin, state, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun repoIssuesOrPulls(
        owner: String,
        repo: String,
        pullRequests: Boolean,
        state: IssueStateFilter,
        forceRefresh: Boolean,
    ): List<IssueOrPullSummary> = repository.getRepoIssuesOrPulls(owner, repo, pullRequests, state, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun issueOrPullDetail(owner: String, repo: String, number: Int, forceRefresh: Boolean): IssueOrPullDetail =
        repository.getIssueOrPullDetail(owner, repo, number, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun pullFiles(owner: String, repo: String, number: Int, forceRefresh: Boolean): List<PullFileChange> =
        repository.getPullFiles(owner, repo, number, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun postComment(owner: String, repo: String, number: Int, body: String) =
        repository.postComment(owner, repo, number, body).getOrThrow()

    @Throws(Exception::class)
    suspend fun setIssueOrPullState(owner: String, repo: String, number: Int, open: Boolean) =
        repository.setIssueOrPullState(owner, repo, number, open).getOrThrow()

    @Throws(Exception::class)
    suspend fun createIssue(owner: String, repo: String, title: String, body: String, labels: List<String>): Int =
        repository.createIssue(owner, repo, title, body, labels).getOrThrow()

    @Throws(Exception::class)
    suspend fun submitReview(owner: String, repo: String, number: Int, event: ReviewEvent, body: String) =
        repository.submitPullReview(owner, repo, number, event, body).getOrThrow()

    @Throws(Exception::class)
    suspend fun merge(owner: String, repo: String, number: Int, method: MergeMethod) =
        repository.mergePullRequest(owner, repo, number, method, null).getOrThrow()

    @Throws(Exception::class)
    suspend fun setDraft(owner: String, repo: String, number: Int, pullRequestId: String, draft: Boolean) =
        repository.setPullRequestDraftState(owner, repo, number, pullRequestId, draft).getOrThrow()

    @Throws(Exception::class)
    suspend fun toggleReaction(
        owner: String,
        repo: String,
        number: Int,
        subjectId: String,
        content: String,
        currentlyReacted: Boolean,
    ): Boolean = repository.toggleReaction(owner, repo, number, subjectId, content, currentlyReacted).getOrThrow()

    @Throws(Exception::class)
    suspend fun updateComment(owner: String, repo: String, number: Int, commentId: String, body: String) =
        repository.updateIssueComment(owner, repo, number, commentId, body).getOrThrow()

    @Throws(Exception::class)
    suspend fun deleteComment(owner: String, repo: String, number: Int, commentId: String) =
        repository.deleteIssueComment(owner, repo, number, commentId).getOrThrow()

    @Throws(Exception::class)
    suspend fun repoLabels(owner: String, repo: String, forceRefresh: Boolean): List<LabelTag> =
        repository.getRepoLabels(owner, repo, forceRefresh).getOrThrow()

    // endregion

    // region Repositories

    @Throws(Exception::class)
    suspend fun viewerRepositories(forceRefresh: Boolean): List<RepoSummary> =
        repository.getViewerRepositories(forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun starredRepositories(forceRefresh: Boolean): List<RepoSummary> =
        repository.getStarredRepositories(forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun repoDetail(owner: String, repo: String, forceRefresh: Boolean): RepoDetail =
        repository.getRepoDetail(owner, repo, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun branches(owner: String, repo: String): List<BranchRef> = repository.getBranches(owner, repo).getOrThrow()

    @Throws(Exception::class)
    suspend fun directory(owner: String, repo: String, path: String, ref: String?, forceRefresh: Boolean): List<TreeEntry> =
        repository.getDirectoryContents(owner, repo, path, ref, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun file(owner: String, repo: String, path: String, ref: String?, forceRefresh: Boolean): FileContent =
        repository.getFileContent(owner, repo, path, ref, forceRefresh).getOrThrow()

    /** README Markdown, or null when the repository has none. */
    @Throws(Exception::class)
    suspend fun readme(owner: String, repo: String, ref: String?, forceRefresh: Boolean): String? =
        repository.getReadme(owner, repo, ref, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun commits(owner: String, repo: String, ref: String?, path: String, forceRefresh: Boolean): List<CommitSummary> =
        repository.getRepoCommits(owner, repo, ref, path, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun commitDetail(owner: String, repo: String, sha: String, forceRefresh: Boolean): CommitDetail =
        repository.getCommitDetail(owner, repo, sha, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun setStarred(owner: String, repo: String, starred: Boolean) =
        repository.setStarred(owner, repo, starred).getOrThrow()

    @Throws(Exception::class)
    suspend fun isWatching(owner: String, repo: String, forceRefresh: Boolean): Boolean =
        repository.getRepoSubscription(owner, repo, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun setWatching(owner: String, repo: String, watching: Boolean) =
        repository.setRepoSubscription(owner, repo, watching).getOrThrow()

    // endregion

    // region Search

    @Throws(Exception::class)
    suspend fun searchRepositories(query: String, forceRefresh: Boolean): List<RepoSummary> =
        repository.searchRepositories(query, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun searchIssuesAndPulls(query: String, forceRefresh: Boolean): List<IssueOrPullSummary> =
        repository.searchIssuesAndPullsGlobal(query, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun searchCode(query: String, forceRefresh: Boolean): List<CodeSearchHit> =
        repository.searchCode(query, forceRefresh).getOrThrow()

    @Throws(Exception::class)
    suspend fun searchUsers(query: String, forceRefresh: Boolean): List<UserSummary> =
        repository.searchUsers(query, forceRefresh).getOrThrow()

    // endregion
}
