import { NextResponse } from "next/server";
import { getConfig } from "@/lib/spree";

/**
 * Facebook data-deletion callback proxy (Meta app → Settings → Basic →
 * Data Deletion Request URL points here, on the public storefront origin).
 *
 * Meta POSTs a form-encoded `signed_request`; the signature can only be
 * verified with the app secret, which lives encrypted in the admin-managed
 * Facebook provider — so this route forwards to the backend endpoint
 * (`POST /api/v3/store/facebook/data_deletion`) and passes its
 * `{ url, confirmation_code }` response through, absolutizing `url` against
 * this request's origin. The backend removes the Facebook identities and
 * logs the request for review; no secrets ever reach the storefront.
 */
export async function POST(request: Request): Promise<NextResponse> {
  let signedRequest: string | null = null;
  try {
    const contentType = request.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
      const body = (await request.json()) as { signed_request?: unknown };
      signedRequest =
        typeof body.signed_request === "string" ? body.signed_request : null;
    } else {
      const form = await request.formData();
      const value = form.get("signed_request");
      signedRequest = typeof value === "string" ? value : null;
    }
  } catch {
    signedRequest = null;
  }

  if (!signedRequest) {
    return NextResponse.json(
      { error: "signed_request is required" },
      { status: 400 },
    );
  }

  try {
    const config = getConfig();
    const baseUrl = config.baseUrl.replace(/\/$/, "");
    const response = await fetch(
      `${baseUrl}/api/v3/store/facebook/data_deletion`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-spree-api-key": config.publishableKey,
        },
        body: JSON.stringify({ signed_request: signedRequest }),
        cache: "no-store",
      },
    );
    const data = (await response.json().catch(() => null)) as {
      url?: string;
      confirmation_code?: string;
      error?: { message?: string };
    } | null;

    if (!response.ok || !data?.url || !data.confirmation_code) {
      return NextResponse.json(
        { error: data?.error?.message ?? "deletion request failed" },
        { status: response.ok ? 502 : response.status },
      );
    }

    const url = data.url.startsWith("/")
      ? new URL(data.url, request.url).toString()
      : data.url;
    return NextResponse.json({
      url,
      confirmation_code: data.confirmation_code,
    });
  } catch {
    return NextResponse.json(
      { error: "deletion request failed" },
      { status: 502 },
    );
  }
}
