# Implementation status

## Implemented in this starter
- Independent Next.js app structure.
- Arabic/English text switching and RTL/LTR layout.
- Supabase email/password sign-in/sign-up page.
- Dashboard and task list, search by task number/title, status and assignee filters, CSV export.
- Create task, change status, nested task relation in the database and subtask panel UI.
- Documents/templates library metadata views.
- Basic team chat composer.
- Supabase schema for workspaces, members, tasks, nested subtasks, comments, attachments metadata, watchers, activity, documents/templates, chat channels/messages, notifications and preferences.
- Tenant-scoped RLS policies and role enum.
- Explicit notification endpoint placeholder that does not claim to send anything.

## Still needed before a real pilot
- First-workspace creation screen calling `create_workspace`.
- Invite/manage members and roles UI.
- Task detail chat and attachment upload controls.
- Load chat history and Supabase Realtime subscription.
- Real in-app notification list/read state.
- Private Storage buckets and tested storage policies.
- Email provider adapter and Teams workflow/Graph adapter.
- Automated notification triggers, retry queue, audit, rate limiting.
- E2E tests and production security review.
