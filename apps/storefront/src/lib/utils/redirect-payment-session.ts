/**
 * Persists the Spree payment-session id across the offsite redirect.
 *
 * eSewa/Khalti return URLs are baked into the payment session at creation
 * time — before the session id is known — so the gateway can't echo
 * `?session=` back to us. Instead we stash the session id locally before
 * navigating away and read it back on the confirm-payment page to complete
 * the right session.
 *
 * Stored in both sessionStorage (same-tab navigation, the normal case) and
 * localStorage (survives tab duplication / session restore).
 */

export interface RedirectSessionRef {
  sessionId: string;
  gateway: "esewa" | "khalti";
}

function storageKey(cartId: string): string {
  return `spree.redirect_session.${cartId}`;
}

function readStorages(key: string): string | null {
  if (typeof window === "undefined") return null;
  try {
    return (
      window.sessionStorage.getItem(key) ?? window.localStorage.getItem(key)
    );
  } catch {
    return null;
  }
}

/** Save the session ref before redirecting to the gateway. */
export function saveRedirectSession(
  cartId: string,
  ref: RedirectSessionRef,
): void {
  if (typeof window === "undefined") return;
  const raw = JSON.stringify(ref);
  try {
    window.sessionStorage.setItem(storageKey(cartId), raw);
  } catch {
    // Storage full / blocked — localStorage below is the fallback.
  }
  try {
    window.localStorage.setItem(storageKey(cartId), raw);
  } catch {
    // Private mode etc. — the return URL params are the last resort.
  }
}

/** Read the session ref on the confirm-payment page. Returns null when absent. */
export function readRedirectSession(cartId: string): RedirectSessionRef | null {
  const raw = readStorages(storageKey(cartId));
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<RedirectSessionRef>;
    if (typeof parsed.sessionId !== "string" || !parsed.sessionId) return null;
    if (parsed.gateway !== "esewa" && parsed.gateway !== "khalti") return null;
    return { sessionId: parsed.sessionId, gateway: parsed.gateway };
  } catch {
    return null;
  }
}

/** Remove the stored ref once the payment is confirmed (or abandoned). */
export function clearRedirectSession(cartId: string): void {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.removeItem(storageKey(cartId));
  } catch {
    // Ignore — best-effort cleanup.
  }
  try {
    window.localStorage.removeItem(storageKey(cartId));
  } catch {
    // Ignore — best-effort cleanup.
  }
}
