"use server";

import type { Order } from "@spree/sdk";
import { updateTag } from "next/cache";
import {
  cacheTagSuffix,
  getAccessToken,
  getCartId,
  getCartOptions,
  getCartToken,
  getClientForSurface,
  getConfig,
  requireCartId,
  type Surface,
} from "@/lib/spree";
import { getCart } from "./cart";
import {
  resolveSurfaceForCart,
  resolveSurfaceForCartVerified,
} from "./checkout";
import { getOrder } from "./orders";
import { actionResult } from "./utils";

function checkoutTag(surface: Surface): string {
  return `checkout${cacheTagSuffix(surface)}`;
}

function cartTag(surface: Surface): string {
  return `cart${cacheTagSuffix(surface)}`;
}

/**
 * Manual QR returns a same-host Active Storage path, which the client
 * component can't absolutize (SPREE_API_URL is server-only) — prefix it
 * here so the checkout form can render the QR <img> directly.
 *
 * Must run on BOTH create and update responses: after any cart-total change
 * (e.g. selecting a shipping rate) the sync flow re-stores external_data
 * from the update response, and a relative path there breaks the QR image
 * against the storefront origin.
 */
function absolutizeQrImageUrl(
  external: Record<string, unknown>,
): Record<string, unknown> {
  if (
    typeof external.qr_image_url === "string" &&
    external.qr_image_url.startsWith("/")
  ) {
    const baseUrl = getConfig().baseUrl.replace(/\/$/, "");
    return { ...external, qr_image_url: `${baseUrl}${external.qr_image_url}` };
  }
  return external;
}

export async function createCheckoutPaymentSession(
  cartId: string,
  paymentMethodId: string,
  externalData?: Record<string, unknown>,
) {
  return actionResult(async () => {
    const surface = await resolveSurfaceForCart(cartId);
    const options = await getCartOptions(surface);
    const id = await requireCartId(surface);
    const session = await getClientForSurface(
      surface,
    ).carts.paymentSessions.create(
      id,
      {
        payment_method_id: paymentMethodId,
        ...(externalData && { external_data: externalData }),
      },
      options,
    );
    updateTag(checkoutTag(surface));
    const external = absolutizeQrImageUrl({
      ...(session.external_data as Record<string, unknown>),
    });
    return { session: { ...session, external_data: external } };
  }, "Failed to create payment session");
}

/**
 * Syncs an existing payment session with the provider (e.g. after the cart
 * total changed). Keeps the provider-side session — and therefore the
 * mounted gateway form — alive, unlike creating a fresh session.
 */
export async function updateCheckoutPaymentSession(
  cartId: string,
  sessionId: string,
  params: { amount?: string; external_data?: Record<string, unknown> } = {},
) {
  return actionResult(async () => {
    const surface = await resolveSurfaceForCart(cartId);
    const options = await getCartOptions(surface);
    const id = await requireCartId(surface);
    const session = await getClientForSurface(
      surface,
    ).carts.paymentSessions.update(id, sessionId, params, options);
    updateTag(checkoutTag(surface));
    const external = absolutizeQrImageUrl({
      ...(session.external_data as Record<string, unknown>),
    });
    return { session: { ...session, external_data: external } };
  }, "Failed to update payment session");
}

/**
 * Creates a direct payment for non-session payment methods
 * (e.g. Check, Cash on Delivery, Bank Transfer).
 */
export async function createDirectPayment(
  cartId: string,
  paymentMethodId: string,
) {
  return actionResult(async () => {
    const surface = await resolveSurfaceForCart(cartId);
    const options = await getCartOptions(surface);
    const id = await requireCartId(surface);
    const payment = await getClientForSurface(surface).carts.payments.create(
      id,
      { payment_method_id: paymentMethodId },
      options,
    );
    updateTag(checkoutTag(surface));
    return { payment };
  }, "Failed to create payment");
}

export async function completeCheckoutPaymentSession(
  cartId: string,
  sessionId: string,
  params?: { session_result?: string; external_data?: Record<string, unknown> },
) {
  return actionResult(async () => {
    const surface = await resolveSurfaceForCart(cartId);
    const options = await getCartOptions(surface);
    const id = await requireCartId(surface);
    const session = await getClientForSurface(
      surface,
    ).carts.paymentSessions.complete(id, sessionId, params, options);
    updateTag(checkoutTag(surface));
    return { session };
  }, "Failed to complete payment session");
}

/**
 * Completes the order. Treats 403 and 422 as success:
 * - 403 = cart already completed (e.g. webhook handler completed it)
 * - 422 = state_lock_version conflict (concurrent request)
 *
 * When the order was already completed (403/422), fetch it from the API
 * so the caller always gets the order data for caching on the thank-you page.
 */
export async function completeCheckoutOrder(
  cartId: string,
  knownSurface?: Surface,
  fallbackSpreeToken?: string,
) {
  const surface = knownSurface ?? (await resolveSurfaceForCart(cartId));
  try {
    const options = await optionsWithTokenFallback(surface, fallbackSpreeToken);
    const order: Order = await getClientForSurface(surface).carts.complete(
      cartId,
      options,
    );
    updateTag(checkoutTag(surface));
    updateTag(cartTag(surface));
    return { success: true as const, order };
  } catch (error: unknown) {
    if (error && typeof error === "object" && "status" in error) {
      const status = (error as { status: number }).status;
      if (status === 403 || status === 422) {
        // Order already completed — try to fetch it so the thank-you page
        // can cache and display it without a second round-trip.
        const completedOrder = await getOrderWithTokenFallback(
          cartId,
          surface,
          fallbackSpreeToken,
        ).catch(() => null);
        updateTag(checkoutTag(surface));
        updateTag(cartTag(surface));
        return { success: true as const, order: completedOrder };
      }
    }
    return {
      success: false as const,
      error:
        error instanceof Error ? error.message : "Failed to complete order",
    };
  }
}

/**
 * Guest order token captured before an offsite redirect (eSewa/Khalti), so
 * the confirm page can verify server-to-server even when the httpOnly cart
 * cookies are unavailable on return. Call this just before navigating away —
 * cookies are still intact at that point.
 */
export async function getRedirectCartAuth(cartId: string): Promise<{
  cartToken?: string;
  cartId?: string;
  surface: Surface;
}> {
  const surface = await resolveSurfaceForCart(cartId);
  const [cartToken, id] = await Promise.all([
    getCartToken(surface),
    getCartId(surface),
  ]);
  return { cartToken, cartId: id, surface };
}

const MANUAL_QR_PROOF_TYPES = ["image/png", "image/jpeg", "image/webp"];
const MANUAL_QR_PROOF_MAX_BYTES = 5 * 1024 * 1024;

function manualQrProofError(file: File): string | null {
  if (!MANUAL_QR_PROOF_TYPES.includes(file.type)) {
    return "Screenshot must be a PNG, JPG or WebP image.";
  }
  if (file.size > MANUAL_QR_PROOF_MAX_BYTES) {
    return "Screenshot must be under 5 MB.";
  }
  return null;
}

/** Raw Store API headers for endpoints the SDK has no method for (multipart). */
async function manualQrApiHeaders(
  surface: Surface,
): Promise<{ baseUrl: string; headers: Record<string, string> }> {
  const config = getConfig();
  const { spreeToken, token } = await getCartOptions(surface);
  const accessToken = token ?? (await getAccessToken().catch(() => undefined));
  return {
    baseUrl: config.baseUrl.replace(/\/$/, ""),
    headers: {
      "x-spree-api-key": config.publishableKey,
      ...(spreeToken ? { "x-spree-token": spreeToken } : {}),
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
  };
}

/**
 * Uploads the payment screenshot to a Manual QR session (checkout flow).
 * Mirrors the backend validation so oversized/wrong-type files fail fast
 * without a wasted upload.
 */
export async function uploadManualQrProof(
  cartId: string,
  sessionId: string,
  file: File,
) {
  const localError = manualQrProofError(file);
  if (localError) return { success: false as const, error: localError };

  const surface = await resolveSurfaceForCart(cartId);
  try {
    const { baseUrl, headers } = await manualQrApiHeaders(surface);
    const id = await requireCartId(surface);
    const form = new FormData();
    form.append("proof_image", file);
    const response = await fetch(
      `${baseUrl}/api/v3/store/carts/${id}/payment_sessions/${sessionId}/proof`,
      { method: "POST", headers, body: form },
    );
    if (!response.ok) {
      const body = await response.json().catch(() => null);
      const message =
        (body as { error?: { message?: string } } | null)?.error?.message ??
        "Failed to upload screenshot.";
      return { success: false as const, error: message };
    }
    updateTag(checkoutTag(surface));
    return { success: true as const };
  } catch (error) {
    return {
      success: false as const,
      error: error instanceof Error ? error.message : "Failed to upload screenshot.",
    };
  }
}

/**
 * Re-uploads a payment screenshot on a completed order after a rejection
 * (customer account order page). Creates a fresh pending payment; the
 * rejected one stays as history.
 */
export async function reuploadManualQrProof(
  orderId: string,
  file: File,
  transactionId?: string,
) {
  const localError = manualQrProofError(file);
  if (localError) return { success: false as const, error: localError };

  // Orders resolve through the DTC surface on the account page; the JWT (or
  // guest order token) authorizes as the order owner server-side.
  const surface = await resolveSurfaceForCart(orderId).catch(() => "dtc" as const);
  try {
    const { baseUrl, headers } = await manualQrApiHeaders(surface);
    const form = new FormData();
    form.append("proof_image", file);
    if (transactionId?.trim()) form.append("transaction_id", transactionId.trim());
    const response = await fetch(
      `${baseUrl}/api/v3/store/orders/${orderId}/manual_qr_proof`,
      { method: "POST", headers, body: form },
    );
    if (!response.ok) {
      const body = await response.json().catch(() => null);
      const message =
        (body as { error?: { message?: string } } | null)?.error?.message ??
        "Failed to upload screenshot.";
      return { success: false as const, error: message };
    }
    return { success: true as const };
  } catch (error) {
    return {
      success: false as const,
      error: error instanceof Error ? error.message : "Failed to upload screenshot.",
    };
  }
}

/**
 * SDK auth options for a surface, falling back to the redirect-stored guest
 * token when the cart cookies are gone (offsite return in private mode,
 * evicted cookies, etc.). Authenticated (JWT) users don't need the fallback.
 */
async function optionsWithTokenFallback(
  surface: Surface,
  fallbackSpreeToken?: string,
): Promise<{ spreeToken: string | undefined; token: string | undefined }> {
  const [options, accessToken] = await Promise.all([
    getCartOptions(surface),
    getAccessToken(),
  ]);
  return {
    spreeToken: options.spreeToken ?? fallbackSpreeToken,
    token: options.token ?? accessToken,
  };
}

async function getOrderWithTokenFallback(
  cartId: string,
  surface: Surface,
  fallbackSpreeToken?: string,
) {
  if (!fallbackSpreeToken) return getOrder(cartId, undefined, surface);
  const cookieOptions = await getCartOptions(surface).catch(() => null);
  if (cookieOptions?.spreeToken) return getOrder(cartId, undefined, surface);
  const token = await getAccessToken().catch(() => undefined);
  return getClientForSurface(surface).orders.get(
    cartId,
    undefined,
    { spreeToken: fallbackSpreeToken, token },
  );
}

async function getCartWithTokenFallback(
  cartId: string,
  surface: Surface,
  fallbackSpreeToken?: string,
) {
  const cart = await getCart(cartId, surface);
  if (cart || !fallbackSpreeToken) return cart;
  // Cookies lost — retry with the redirect-stored guest token on both
  // surfaces; whichever credentials match wins.
  try {
    const token = await getAccessToken().catch(() => undefined);
    return await getClientForSurface(surface).carts.get(cartId, {
      spreeToken: fallbackSpreeToken,
      token,
    });
  } catch {
    return null;
  }
}

/**
 * Confirms payment and completes the order after returning from an offsite
 * payment gateway (e.g. CashApp, 3D Secure).
 *
 * Redirect gateways (eSewa, Khalti) pass their return payload through
 * `externalData` — e.g. `{ data }` (eSewa's base64 redirect payload) or
 * `{ pidx }` (Khalti). The backend verifies server-to-server and never
 * trusts the client payload for the verdict.
 *
 * `fallbackSpreeToken` is the guest order token captured before the offsite
 * redirect (see `getRedirectCartAuth` + `saveRedirectSession`). It is only
 * used when the httpOnly cart cookies are unavailable on return.
 */
export async function confirmPaymentAndCompleteCart(
  cartId: string,
  sessionId?: string,
  sessionResult?: string,
  redirectResult?: string,
  adyenSessionId?: string,
  externalData?: Record<string, unknown>,
  fallbackSpreeToken?: string,
): Promise<
  { success: true; order: unknown } | { success: false; error: string }
> {
  // Cookies may have been cleared during the offsite redirect, so verify the
  // surface against the cart's own channel rather than trusting the cookie.
  const verifiedSurface = await resolveSurfaceForCartVerified(cartId);
  let surface: Surface;
  if (verifiedSurface === "unverified") {
    // No cart could be fetched for verification (cookies lost, cart already
    // completed, or transient backend failure). Fall back to the cookie
    // surface so a transient doesn't hard-block checkout — the explicit
    // cartId + fallback token below still scope every request to this cart,
    // and the backend verifies payment server-to-server.
    // If the cart truly can't be fetched, the getCart branch below resolves
    // it as an already-completed order instead of surfacing a retry loop.
    surface = await resolveSurfaceForCart(cartId);
  } else {
    surface = verifiedSurface;
  }
  try {
    const cart = await getCartWithTokenFallback(
      cartId,
      surface,
      fallbackSpreeToken,
    );
    if (!cart) {
      // Cart not found — the order may already be completed (e.g. by webhook
      // or a double-submit). Try fetching it as a completed order on this
      // surface, then on the other surface, before giving up.
      const completedOrder =
        (await getOrderWithTokenFallback(cartId, surface, fallbackSpreeToken).catch(
          () => null,
        )) ??
        (await getOrderWithTokenFallback(
          cartId,
          surface === "dtc" ? "wholesale" : "dtc",
          fallbackSpreeToken,
        ).catch(() => null));
      return { success: true, order: completedOrder };
    }

    if (cart.current_step === "complete") {
      return { success: true, order: cart };
    }

    if (sessionId) {
      const options = await optionsWithTokenFallback(
        surface,
        fallbackSpreeToken,
      );
      const completeParams =
        sessionResult || externalData
          ? {
              ...(sessionResult ? { session_result: sessionResult } : {}),
              ...(externalData ? { external_data: externalData } : {}),
            }
          : undefined;
      // Use the explicit cartId from the return URL — the cookie cart id may
      // be gone after the offsite redirect.
      const completeResult = await getClientForSurface(
        surface,
      ).carts.paymentSessions.complete(
        cartId,
        sessionId,
        completeParams,
        options,
      );
      if (completeResult.status === "failed") {
        return {
          success: false,
          error: "Payment was not successful. Please try again.",
        };
      }
    } else if (redirectResult) {
      // Adyen redirect flow: redirectResult is appended by Adyen to the return URL.
      // Pass it to the backend which resolves the session and processes the redirect.
      const options = await optionsWithTokenFallback(
        surface,
        fallbackSpreeToken,
      );
      const completeResult = await getClientForSurface(
        surface,
      ).carts.paymentSessions.complete(
        cartId,
        adyenSessionId ?? "",
        {
          external_data: {
            redirect_result: redirectResult,
          },
        },
        options,
      );
      if (completeResult.status === "failed") {
        return {
          success: false,
          error: "Payment was not successful. Please try again.",
        };
      }
    } else if (externalData && Object.keys(externalData).length > 0) {
      // eSewa/Khalti returned without a resolvable session id (storage was
      // cleared while offsite). We can't verify without the session, so fail
      // with a resumable message instead of attempting an unpaid completion.
      return {
        success: false,
        error:
          "Payment session expired. Please return to checkout and try again.",
      };
    }

    // Pass the verified surface so completion doesn't re-resolve from the
    // (possibly cleared) cookie.
    const result = await completeCheckoutOrder(
      cartId,
      surface,
      fallbackSpreeToken,
    );
    if (result.success) {
      return { success: true, order: result.order };
    }
    return { success: false, error: result.error };
  } catch (error) {
    return {
      success: false,
      error:
        error instanceof Error
          ? error.message
          : "Failed to confirm payment. Please try again.",
    };
  }
}
