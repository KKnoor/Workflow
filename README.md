# WorkFlow Hub — Bilingual Work Management SaaS starter

Independent Arabic/English work-management platform starter. It does **not** modify or replace the existing Multitools project.

## Included
- Next.js App Router + TypeScript + Tailwind
- Arabic/English UI with RTL/LTR switch
- Supabase Auth client setup
- Dashboard with summary cards, task filters, CSV export
- Tasks and nested subtasks UI (database supports parent-child relationships)
- Documents and templates library views
- Team chat UI (database schema supports channel messages)
- In-app notifications table and notification preferences
- Supabase SQL schema with tenant-aware tables, RLS policies, roles, and helper functions
- Server route placeholder for email/Teams notifications; integrations remain disabled until configured

## Requirements
- Node.js 20+
- Supabase project
- Optional: email provider credentials and Microsoft Teams webhook/Workflow URL

## Run locally
1. Extract the ZIP.
2. Copy `.env.example` to `.env.local` and fill in Supabase project URL and anon key.
3. In Supabase SQL Editor, run `supabase/schema.sql`.
4. In Supabase Authentication > URL Configuration, set the local URL to `http://localhost:3000`.
5. Run:
   ```bash
   npm install
   npm run dev
   ```
6. Open `http://localhost:3000`, create a user, then create a workspace from the UI.

## Supabase setup notes
- Enable Email auth. For a private pilot, invite users from Supabase Auth or implement the invite flow before public launch.
- After signup, the app calls a database function to create a workspace and membership. Check the SQL policies before production use.
- Supabase Storage buckets `work-files` and `avatars` are referenced in the schema notes; create private buckets and configure storage policies before enabling uploads.
- Row Level Security is enabled on tenant data. Test with multiple accounts before using real company data.

## Notifications
The app stores in-app notifications. The `/api/notifications/dispatch` endpoint is a guarded integration placeholder and returns a clear configuration response until credentials are supplied. Email and Microsoft Teams delivery are **not claimed as active**. Configure provider credentials and add server-side event triggers before production.
- Email: set up an email provider and implement sending in the route.
- Teams: create a Teams Workflow webhook or Microsoft Graph app, then store its secret server-side only.
- Never expose service-role keys, mail credentials, or Teams webhook URLs to the browser.

## Main files
- `src/app/page.tsx` — main app/dashboard/tasks/library/chat
- `src/app/login/page.tsx` — authentication
- `src/lib/supabase.ts` — Supabase browser client
- `src/lib/i18n.ts` — Arabic/English strings
- `supabase/schema.sql` — database schema and RLS
- `.env.example` — environment variable template

## Current maturity
This is a runnable starter/MVP scaffold, not a production-certified SaaS. Auth and Supabase data access are wired; the UI includes demo fallback data when environment variables are absent. Before selling it, complete invitation flows, storage upload UX, real-time chat subscriptions, email/Teams dispatch triggers, audit logging, rate limiting, backups, and security review.
