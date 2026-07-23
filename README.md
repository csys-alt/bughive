<<<<<<< HEAD
# BugHive

BugHive is a mobile-first engineering logbook for developers and QA engineers.

It helps engineers capture private debugging notes, bug reports, feature ideas,
research, and technical investigations, then optionally sync selected logs to
GitHub Issues.

## Product Shape

- Supabase is the source of truth.
- GitHub is only a manual synchronization target.
- Home and repository detail screens load from Supabase only.
- GitHub API calls happen only when connecting a repository or syncing a log.

## Current App Flow

1. Continue with GitHub through Supabase Auth.
2. View repositories registered in BugHive.
3. Add a GitHub repository URL.
4. Create engineering logs as local drafts.
5. Optionally sync a saved log to GitHub Issues.

## Environment

Copy `.env-example` to `.env`, then set:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `GITHUB_OAUTH_REDIRECT_URL`

After changing Nylo environment values, regenerate the app env file before
building:

```bash
dart run nylo_framework:main make:env
```
=======
[![Review Assignment Due Date](https://classroom.github.com/assets/deadline-readme-button-22041afd0340ce965d47ae6ef1cefeee28c7c493a6346c4f15d667ab976d596c.svg)](https://classroom.github.com/a/zjus_4YR)
>>>>>>> c2bd9eee583485e74171ad96be89c5803c30ab15
