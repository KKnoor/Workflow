# Email and Microsoft Teams notifications

The schema stores user preferences and in-app notifications. Delivery to email/Teams is not implemented yet and must not be considered active.

Recommended implementation:
1. Add a server-only event dispatcher (Supabase Edge Function or authenticated Next.js server action).
2. Invoke it after task assignment, due-date changes, comments, and mentions.
3. Insert an in-app row into `notifications` for each recipient.
4. For email, use an email provider SDK with `EMAIL_PROVIDER_API_KEY` and `EMAIL_FROM`.
5. For Teams, use a Microsoft Teams Workflow webhook for a channel, or Microsoft Graph with tenant/admin consent for direct messages.
6. Store Teams endpoints and provider credentials only in server-side secrets; do not expose them in `NEXT_PUBLIC_*`.
7. Authenticate event calls (service secret or signed webhook), validate workspace membership, and rate-limit dispatch.
8. Record provider response IDs and failures for retry/audit.

`src/app/api/notifications/dispatch/route.ts` deliberately returns HTTP 501 and states that no message was sent until an actual provider adapter is implemented.
