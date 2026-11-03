# Omniscient · Incident Knowledge

A private RCA workspace built with Next.js, React, TypeScript and Supabase, deployed on Vercel.

Inspired by the requirements and phase-1 HLD from [jatin-mishra/Omniscient](https://github.com/jatin-mishra/Omniscient). This repository contains an independently built implementation, not a fork of application code.

## Working features

- Email/password authentication, account confirmation, protected workspace and sign-out.
- Ten-section RCA editor, severity and sensitivity metadata, Markdown import/export and completeness checks.
- Source-linked keyword evidence search and explicit abstention when nothing matches.
- Action tracking with owners, deadlines, priorities, editable status and overdue indicators.
- Team profiles, completeness-gated review requests, read-only client audit history and JSON export.
- PostgreSQL row-level security, atomic audited writes and revision checks to prevent stale edits.
- Optional sample incidents loaded only on explicit request into an empty workspace.

## Run locally

Use Node.js 24. Copy `.env.example` to `.env.local`, configure the Supabase project URL and **publishable** key, then run:

```sh
npm ci
npm run dev
```

Apply `database/schema.sql` once to a new Supabase project. It creates owner-scoped records, client-read-only audit tables, validation triggers and constrained RPCs. Never put service-role or secret keys in public variables.

In Supabase Authentication URL Configuration, set Site URL to your Vercel production origin and allow `<origin>/auth/callback`. New accounts confirm their email before signing in. The application uses Supabase SSR cookies and validates users server-side; it does not trust caller-supplied identity headers.

## Verification

```sh
npm run typecheck
npm test
npm run build
```

`tests/security.sql` checks live database authorization, immutable client audit access, optimistic concurrency, completeness guards, action ownership and source authorization. It creates disposable fixtures inside a transaction and rolls back all rows. Run through the Supabase SQL editor or an administrative connection in a dedicated project.

## Honest scope

This is a foundation release. Search returns original source excerpts, not AI-generated answers. AI synthesis, vectors/reranking, independent reviewer approvals, team/group authorization, company-source ingestion and Slack/Jira/PagerDuty integrations remain pending. Team profiles and sensitivity labels are metadata; all content is private to its signed-in owner. Audit tables are append-only to application clients, not compliance-grade WORM storage. The 5,000-user and indexing/latency targets have not been load-tested.

The original ChatGPT-hosted version uses a separate database and identity provider. Its existing records are not automatically migrated into this deployment.
