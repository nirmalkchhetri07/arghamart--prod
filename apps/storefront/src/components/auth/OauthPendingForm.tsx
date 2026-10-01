"use client";

import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import type { OauthPendingCode } from "@/lib/auth/oauth-client";
import { completeOauthLogin } from "@/lib/data/oauth";

export interface PendingOAuthState {
  code: OauthPendingCode;
  pendingOAuth: string;
}

/**
 * Inline completion form for the two social sign-ins that cannot finish in
 * one round trip:
 *
 * - `email_missing` — the provider shared no email; the customer supplies
 *   one (if it turns out to belong to an existing account, the backend
 *   rotates this form into password mode with a fresh pending token).
 * - `account_exists_confirm_required` — the provider email is unverified
 *   and already registered; the customer proves ownership with the account
 *   password before the identity links.
 *
 * Pending tokens are single-use, so every submit consumes the token it was
 * given; a rotated token replaces the current one.
 */
export function OauthPendingForm({
  state,
  onAuthed,
  onCancel,
}: {
  state: PendingOAuthState;
  onAuthed: () => void | Promise<void>;
  onCancel: () => void;
}) {
  const t = useTranslations("oauth");
  const [pending, setPending] = useState(state);
  const [mode, setMode] = useState<"email" | "password">(
    state.code === "email_missing" ? "email" : "password",
  );
  const [value, setValue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (busy || value.length === 0) return;
    setBusy(true);
    setError(null);
    try {
      const result = await completeOauthLogin({
        pendingOAuth: pending.pendingOAuth,
        ...(mode === "email" ? { email: value } : { password: value }),
      });
      if (result.success) {
        await onAuthed();
        return;
      }
      if (
        result.pendingOAuth &&
        result.errorCode === "account_exists_confirm_required"
      ) {
        // The supplied email belongs to an account: switch to password proof
        // with the freshly minted token.
        setPending({
          code: "account_exists_confirm_required",
          pendingOAuth: result.pendingOAuth,
        });
        setMode("password");
        setValue("");
        return;
      }
      if (result.errorCode === "email_missing") {
        setError(t("invalidEmail"));
        setValue("");
        return;
      }
      // invalid_credentials (wrong password), invalid_token (expired or
      // already-used pending token) and anything else surface inline; the
      // back link restarts the sign-in when the token is dead.
      setError(t(`errors.${result.errorCode ?? "failed"}`));
    } catch {
      setError(t("errors.failed"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-3">
      <div>
        <h2 className="text-sm font-semibold text-gray-900">
          {mode === "email" ? t("emailMissingTitle") : t("accountExistsTitle")}
        </h2>
        <p className="mt-1 text-sm text-gray-600">
          {mode === "email" ? t("emailMissingHint") : t("accountExistsHint")}
        </p>
      </div>
      <div className="flex flex-col gap-1">
        <label
          htmlFor="oauth-pending-input"
          className="text-sm font-medium text-gray-900"
        >
          {mode === "email" ? t("emailLabel") : t("passwordLabel")}
        </label>
        <input
          id="oauth-pending-input"
          type={mode === "email" ? "email" : "password"}
          autoComplete={mode === "email" ? "email" : "current-password"}
          value={value}
          onChange={(event) => setValue(event.target.value)}
          required
          className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        />
        {error && (
          <p role="alert" className="text-sm text-red-600">
            {error}
          </p>
        )}
      </div>
      <Button type="submit" size="lg" className="w-full" disabled={busy}>
        {busy ? t("completingSignIn") : t("continueSignIn")}
      </Button>
      <button
        type="button"
        onClick={onCancel}
        className="text-sm text-primary hover:text-primary/70 font-medium self-center"
      >
        {t("backToSignIn")}
      </button>
    </form>
  );
}
