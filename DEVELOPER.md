# BugHive — Developer Guide

Mobile-first engineering logbook. Capture debugging notes, structure bug reports, optionally sync to GitHub Issues.

**Not a Jira replacement.** The app captures engineering context *before* an issue exists.

**Status:** Release candidate (v1.0.0), stable. **GitHub login is the only auth path** — offline mode was removed entirely (commits `cb3db34`, `be92362`). See `RELEASE.md` for the signed-APK build & GitHub Release flow.

---

## Quick Start

```bash
# 1. Clone and install
git clone <repo-url> && cd bughive
flutter pub get

# 2. Environment
cp .env-example .env
# Fill in SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY
# Run the Nylo env generator:
dart run nylo_framework:main make:env

# 3. Supabase
# Paste SUPABASE_SETUP.md SQL into Supabase SQL Editor → Run
# Configure Auth → Providers → GitHub (client ID + secret)
# Configure Auth → URL Configuration → add redirect: bughive://auth-callback

# 4. Run
flutter run
```

### Environment Variables

| Variable | Required | What it does |
|---|---|---|
| `SUPABASE_URL` | **Yes** | `https://<ref>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | **Yes** | Supabase anon key (never service role) |
| `GITHUB_OAUTH_REDIRECT_URL` | Yes | `bughive://auth-callback` — must match Supabase Auth redirect list |
| `APP_ENV` | No | `developing` or `production` (controls Supabase debug logs). Set to `production` for release builds |
| `APP_DEBUG` | No | `true`/`false`. Set to `false` for release builds |
| `SHOW_SPLASH_SCREEN` | No | `true`/`false` |

After editing `.env`, regenerate the encrypted env file:

```bash
dart run nylo_framework:main make:env
```

---

## Architecture

```
Flutter App (Nylo framework)
    │
    ├── SupabaseService ── Supabase (source of truth)
    │       ├── Auth (GitHub OAuth)
    │       ├── PostgreSQL (profiles, repositories, engineering_logs, attachments)
    │       └── Storage (bughive bucket — screenshots)
    │
    └── GithubService ── GitHub REST API (sync target only)
            ├── GET  /repos/{owner}/{name}
            ├── GET  /repos/{owner}/{name}/issues?state=all
            ├── POST /repos/{owner}/{name}/issues
            └── PATCH /repos/{owner}/{name}/issues/{number}
```

**Key rule:** GitHub API is called **only** when adding a repository or syncing/closing an issue. Home screen and detail screens load exclusively from Supabase.

---

## Project Structure

```
lib/
├── main.dart                          # Nylo.init() entry point
├── app/
│   ├── controllers/
│   │   ├── controller.dart            # Base (empty)
│   │   ├── auth_controller.dart       # GitHub login, logout, reconnect, account deletion
│   │   ├── home_controller.dart       # Workspace data loading
│   │   ├── github_controller.dart     # GitHub ↔ Supabase sync orchestration
│   │   └── log_controller.dart        # Log CRUD + sync + attachments
│   ├── models/
│   │   ├── user.dart                  # Profile (extends Nylo Model)
│   │   ├── repository.dart            # GitHub repo registration
│   │   ├── engineering_log.dart       # Core log + enums
│   │   └── attachment.dart            # Screenshot metadata
│   ├── services/
│   │   ├── supabase_service.dart      # All Supabase ops (auth, DB, storage) + secure GitHub-token cache
│   │   └── github_service.dart        # GitHub REST API wrapper (Dio)
│   └── providers/                     # Nylo boot providers (mostly boilerplate)
├── bootstrap/
│   ├── boot.dart                      # Splash → SupabaseService.init → providers
│   ├── decoders.dart                  # Model + controller factory registrations
│   ├── env.g.dart                     # Auto-generated encrypted env (DO NOT EDIT)
│   └── theme.dart                     # Light + dark theme definitions
├── config/
│   ├── app.dart                       # AppConfig — reads all env vars
│   ├── storage_keys.dart              # NyStorage key constants
│   └── design.dart                    # Font (JetBrains Mono), logo, loader
├── resources/
│   ├── pages/                         # All screens (see Pages section)
│   ├── widgets/                       # Reusable UI components
│   └── themes/                        # Theme data files
└── routes/
    ├── router.dart                    # Route table
    └── guards/
        └── auth_route_guard.dart      # Exists but not wired to routes
```

---

## Data Models

### `EngineeringLog`

The core domain object.

| Field | Type | Notes |
|---|---|---|
| `id` | `String?` | UUID from Supabase |
| `repoId` | `String` | FK → repositories |
| `userId` | `String` | FK → profiles |
| `title` | `String` | Issue title |
| `description` | `String` | Markdown body |
| `type` | `EngineeringLogType` | `BUG`, `FEATURE`, `RESEARCH`, `NOTE` |
| `severity` | `Severity` | `LOW`, `MEDIUM`, `HIGH`, `CRITICAL` |
| `environment` | `String` | Free text (e.g. "Android 16, Flutter 3.x") |
| `labels` | `List<String>` | Stored as JSONB. Uses GitHub default label set |
| `syncStatus` | `SyncStatus` | `LOCAL` → `SYNCED` → `CLOSED` |
| `githubIssueNumber` | `int?` | Set after GitHub sync |
| `createdAt` | `DateTime?` | GitHub `created_at` for imports, `now()` for local |
| `updatedAt` | `DateTime?` | App sync time (not GitHub's `updated_at`) |

**Computed:** `isSynced` = status ≠ LOCAL, `isClosed` = status == CLOSED.

### `Repository`

| Field | Type | Notes |
|---|---|---|
| `id` | `String?` | UUID |
| `userId` | `String?` | FK → profiles |
| `githubRepoId` | `int` | GitHub's numeric repo ID |
| `owner` | `String` | GitHub owner/org |
| `name` | `String` | Repo name |
| `url` | `String` | `html_url` from GitHub |
| `lastSync` | `DateTime?` | Updated after issue import |
| `createdAt` | `DateTime?` | GitHub's `created_at` for the repo |

**Computed:** `fullName` → `"owner/name"`.

### `User` (extends Nylo `Model`)

| Field | Type |
|---|---|
| `id` | `String?` (auth.users UUID) |
| `githubId` | `String?` |
| `username` | `String?` |
| `avatarUrl` | `String?` |
| `createdAt` | `DateTime?` |

### `Attachment`

| Field | Type |
|---|---|
| `id` | `String?` |
| `logId` | `String` (FK → engineering_logs) |
| `fileUrl` | `String` (Supabase Storage public URL) |
| `createdAt` | `DateTime?` |

---

## Services

### `SupabaseService` — the data layer

Every data operation goes through this service. It is **online-only** — the app
requires a live Supabase session (GitHub login). There is no offline/local
storage fallback.

#### Supabase Tables Touched

| Table | Operations |
|---|---|
| `profiles` | Upsert on login (`loadProfile`) |
| `repositories` | `fetchRepositories`, `saveRepository`, `markRepositorySynced`, `deleteRepository` |
| `engineering_logs` | `fetchEngineeringLogs`, `createEngineeringLog`, `updateEngineeringLog`, `markLogSynced`, `markLogFinished`, `deleteEngineeringLog`, `fetchLogCounts` |
| `attachments` | `createAttachment`, `fetchAttachments` |
| `storage.bughive` | `uploadScreenshot` → `logs/{logId}/{timestamp}.png` |

#### Auth Methods

| Method | What |
|---|---|
| `signInWithGithub()` | OAuth with scopes: `repo read:user user:email notifications` |
| `signOut()` | Global sign-out (revokes refresh token server-side across devices); falls back to local sign-out if offline. Clears the cached GitHub token |
| `deleteCloudAccountData()` | Permanently deletes this account's storage files + `profiles` row (cascades to repositories/logs/attachments) + cached token |
| `getGithubAccessToken()` | Prefers live `session.providerToken`; falls back to the token cached in secure storage (Supabase doesn't restore `providerToken` across app restarts) |
| `clearGithubAccessToken()` | Deletes the cached token for the current user |

#### GitHub Token Caching

The GitHub OAuth access token is cached in `flutter_secure_storage` (Android
Keystore), keyed per user. This is necessary because Supabase only exposes
`session.providerToken` immediately after sign-in, not across app restarts —
so the token is persisted on the `SIGNED_IN` event and read back for later
GitHub API calls.

### `GithubService` — GitHub REST API wrapper

Pure HTTP wrapper using **Dio**. No Supabase interaction.

| Method | GitHub API | When Called |
|---|---|---|
| `getRepository(url)` | `GET /repos/{owner}/{name}` | Adding a repository |
| `listIssues(repo)` | `GET /repos/{o}/{n}/issues?state=all&per_page=100` | After adding a repo (import) |
| `createIssue(repo, log)` | `POST /repos/{o}/{n}/issues` | User taps "Sync GitHub" |
| `updateIssue(repo, log, #)` | `PATCH /repos/{o}/{n}/issues/{#}` | Re-syncing edited log |
| `closeIssue(repo, #)` | `PATCH …` with `state: "closed"` | User closes/deletes synced issue |
| `buildIssueBody(log)` | — | Formats markdown: Description, Environment, Severity, Evidence |
| `parseRepositoryUrl(url)` | — | Validates `github.com/owner/name` format |

**All methods throw `GithubServiceException` on failure** (wraps Dio errors + GitHub API error messages).

---

## Controllers

Controllers are the orchestration layer between pages and services.

### `AuthController`

| Method | Flow |
|---|---|
| `continueWithGithub()` | → `supabase.signInWithGithub()` (opens browser) |
| `reconnectGithub()` | Clears the known-bad cached token → re-runs `signInWithGithub()` (used when a token becomes invalid) |
| `loadProfile()` | → `supabase.loadProfile()` |
| `listenForSignedIn(cb)` | Subscribes to `supabase.authStateChanges` stream |
| `signOut()` | → `supabase.signOut()` → navigate to LoginPage |
| `deleteAccount()` | → `supabase.deleteCloudAccountData()` → `signOut()` |

### `HomeController`

| Method | Flow |
|---|---|
| `loadWorkspace()` | Fetches all repos + log counts per repo. Returns `List<RepositoryWorkspaceItem>` |
| `deleteRepository(repo)` | → `supabase.deleteRepository()` |

### `GithubController`

The heaviest controller — all GitHub ↔ Supabase sync lives here.

| Method | Flow |
|---|---|
| `addRepository(url)` | Validate URL → `github.getRepository()` → `supabase.saveRepository()` → `_importGithubIssues()` → `supabase.markRepositorySynced()` |
| `syncLog(repo, log, urls)` | Handles 3 cases: local repo (promote first), already-synced (update issue), new sync (create issue). Uploads attachments. |
| `closeIssue(repo, log)` | → `github.closeIssue()` → `supabase.markLogFinished()` |
| `_importGithubIssues(repo)` | → `github.listIssues()` → for each: create or update engineering_log in Supabase (deduped by issue number) |

**Import behavior:** New issues get `createdAt` from GitHub but `updatedAt = DateTime.now()` (app sync time). Existing imports get their status/createdAt refreshed.

### `LogController`

| Method | Flow |
|---|---|
| `createLocalLog(...)` | → `supabase.createEngineeringLog()` + save attachments |
| `createAndSyncLog(...)` | Create locally first → `github.syncLog()`. On failure: throws `LogSyncFailure` (preserves saved log) |
| `retrySync(repo, log)` | Re-attempts `github.syncLog()` |
| `updateLog(log)` | → `supabase.updateEngineeringLog()` |
| `markFinished(repo, log)` | → `github.closeIssue()` |
| `deleteLog(repo, log)` | If synced → close as "not_planned" → `supabase.deleteEngineeringLog()` |

---

## Pages & Routes

| Route | Page | Controller | Purpose |
|---|---|---|---|
| `/login` (initial) | `LoginPage` | `AuthController` | GitHub OAuth (only auth path) |
| `/home` | `HomePage` | `HomeController` | Repo workspace list |
| `/repositories/add` | `AddRepositoryPage` | `GithubController` | Add repo by URL |
| `/repository` | `RepositoryDetailPage` | `LogController` | Log list with tabs: All / Open / Finished |
| `/logs/create` | `CreateLogPage` | `LogController` | Full log form + attachments |
| `/logs/detail` | `LogDetailPage` | `LogController` | View/edit log + sync/close/delete |
| `/profile` | `ProfilePage` | `AuthController` | User info + logout + full account deletion |
| `/not-found` | `NotFoundPage` | — | Fallback |

**Navigation pattern:** Pages push with `routeTo()` and reload data on `pop` using `.then((_) => _load())`.

---

## Widgets

| Widget | Where Used | What It Does |
|---|---|---|
| `RepoCard` | HomePage | Repo summary: name, owner, metrics, time |
| `LogCard` | RepositoryDetailPage | Log summary: type badge, title, severity, status, labels |
| `TimeMetaText` | RepoCard, LogCard | `"5 JUL 2026 - Just now"` — left=fixed date, right=relative (auto-refreshes every 60s) |
| `SeverityChip` | LogCard, LogDetailPage | Color-coded: LOW=blue, MEDIUM=green, HIGH=orange, CRITICAL=red |
| `GithubLabelPicker` | CreateLogPage, LogDetailPage | 9 default GitHub labels as toggle chips |
| `DarkDropdownField` | CreateLogPage, LogDetailPage | Themed dropdown for type/severity |
| `Loader` | Multiple | Pulsing bug icon animation |
| `SplashScreen` | Boot | Logo + rotating dots |
| `MainWidget` | Root | MaterialApp wrapper, forces `ThemeMode.dark` |

---

## Supabase Database Schema

4 tables, all with Row Level Security (user can only access own data).

```sql
profiles         (id PK → auth.users, github_id, username, avatar_url, created_at)
repositories     (id PK, user_id FK→profiles, github_repo_id, owner, name, url, last_sync, created_at)
                 UNIQUE(user_id, github_repo_id)
engineering_logs (id PK, repo_id FK→repositories, user_id FK→profiles,
                 title, description, type, severity, environment,
                 labels JSONB, sync_status, github_issue_number,
                 created_at, updated_at)
                 -- auto-updated_at trigger on UPDATE
attachments      (id PK, log_id FK→engineering_logs, file_url, created_at)
                 -- CASCADE DELETE from engineering_logs
```

**Storage bucket:** `bughive` (public read). Path: `logs/{log_id}/{timestamp}.png`.

**Full setup SQL:** See `SUPABASE_SETUP.md`. Known hotfixes documented there for delete permissions and sync_status constraints.

---

## Sync Status Lifecycle

```
LOCAL  ──(user taps "Sync GitHub")──→  SYNCED  ──(user closes issue)──→  CLOSED
                                         │
                                         ├── updateIssue() on re-sync
                                         └── closeIssue(not_planned) on delete
```

---

## Timestamp Conventions

| Field | Source | Meaning |
|---|---|---|
| `repository.createdAt` | GitHub API `created_at` | When the repo was created on GitHub |
| `repository.lastSync` | `DateTime.now()` after import | When BugHive last synced issues |
| `log.createdAt` | GitHub `created_at` (imported) or `now()` (local) | When the issue/log was originally created |
| `log.updatedAt` | Always `DateTime.now()` at sync time | When BugHive last touched this log |

`TimeMetaText` displays: `"{createdAt formatted} - {updatedAt relative}"` — e.g. `"12 MAY 2026 - 3 months ago"`.

---

## Dependencies

| Package | Version | Why |
|---|---|---|
| `nylo_framework` | ^7.1.24 | App framework (routing, state, storage, DI) |
| `supabase_flutter` | ^2.15.4 | Auth + DB + Storage SDK |
| `google_fonts` | ^8.1.0 | JetBrains Mono font |
| `file_picker` | ^12.0.0-beta.7 | Screenshot attachment selection |
| `font_awesome_flutter` | ^11.0.0 | GitHub icon on login button |
| `url_launcher` | ^6.3.2 | Open GitHub URLs in browser |
| `intl` | ^0.20.2 | Date formatting utilities |

**Dart SDK:** `^3.10.7`

---

## Conventions

- **Dark mode only.** `Main` widget hardcodes `ThemeMode.dark`.
- **Font:** JetBrains Mono everywhere (via `google_fonts`).
- **Online-only.** All IDs are Supabase UUIDs; a new log lives in the DB with `sync_status = LOCAL` until pushed to GitHub (there is no on-device local store).
- **Swipe-to-delete** is two-step: first swipe shows confirm overlay, second swipe executes.
- **Error handling:** Services throw typed exceptions (`GithubServiceException`, `SupabaseServiceException`). Controllers catch and surface to UI via toast or inline error state.
- **No ORM.** Models do manual `fromJson`/`toSupabaseJson` with `_dateValue`/`_intValue` helpers.
- **Auth guard** (`auth_route_guard.dart`) exists but is not applied to routes. Login page handles auth check manually.

---

## Common Tasks

### Add a new model field

1. Add field to model class + `fromJson` + `toSupabaseJson` + `copyWith`
2. Add column in Supabase SQL editor

### Add a new page

1. Create `lib/resources/pages/my_page.dart` extending `NyStatefulWidget<MyController>`
2. Add route in `lib/routes/router.dart`
3. Register controller factory in `lib/bootstrap/decoders.dart`

### Add a new GitHub API call

1. Add method to `GithubService` (Dio request)
2. Orchestrate from `GithubController`
3. Surface to UI via controller method

### Regenerate env after editing `.env`

```bash
dart run nylo_framework:main make:env
```

This produces `lib/bootstrap/env.g.dart` — **never edit that file manually**.
