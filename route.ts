import { NextResponse } from "next/server";

export async function POST(request: Request) {
  // Integration intentionally fails closed until provider-side implementation is configured.
  const hasEmail = Boolean(process.env.EMAIL_PROVIDER_API_KEY && process.env.EMAIL_FROM);
  const hasTeams = Boolean(process.env.TEAMS_WORKFLOW_WEBHOOK_URL);
  const body = await request.json().catch(() => ({}));
  if (!hasEmail && !hasTeams) {
    return NextResponse.json({
      ok: false,
      message: "Notification delivery is not configured. In-app notifications can be stored in Supabase; configure email and/or Teams server-side credentials and implement event dispatch before enabling this endpoint.",
      configured: { email: hasEmail, teams: hasTeams },
      acceptedEvent: Boolean(body?.event)
    }, { status: 501 });
  }
  // Safety: no message is sent here yet. This endpoint reports readiness only;
  // wire a provider SDK and authenticated internal event source before production use.
  return NextResponse.json({
    ok: false,
    message: "Credentials detected, but delivery adapter is not implemented yet. No notification was sent.",
    configured: { email: hasEmail, teams: hasTeams }
  }, { status: 501 });
}
