import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/spree", () => ({
  getConfig: () => ({
    baseUrl: "http://backend:3000/",
    publishableKey: "pk-test",
  }),
}));

import { POST } from "@/app/api/facebook/data-deletion/route";

const fetchMock = vi.fn();

function backendResponse(
  body: unknown,
  { ok = true, status = 200 } = {},
): Response {
  return {
    ok,
    status,
    json: async () => body,
  } as unknown as Response;
}

function deletionRequest(
  body: string,
  contentType = "application/x-www-form-urlencoded",
): Request {
  return new Request("https://shop.example/api/facebook/data-deletion", {
    method: "POST",
    headers: { "content-type": contentType },
    body,
  });
}

describe("POST /api/facebook/data-deletion", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal("fetch", fetchMock);
  });

  it("forwards the signed_request and absolutizes the status URL", async () => {
    fetchMock.mockResolvedValue(
      backendResponse({
        url: "/data-deletion-status?code=abc123",
        confirmation_code: "abc123",
      }),
    );

    const response = await POST(deletionRequest("signed_request=sig.payload"));
    const body = (await response.json()) as {
      url: string;
      confirmation_code: string;
    };

    expect(response.status).toBe(200);
    expect(body).toEqual({
      url: "https://shop.example/data-deletion-status?code=abc123",
      confirmation_code: "abc123",
    });

    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("http://backend:3000/api/v3/store/facebook/data_deletion");
    expect(JSON.parse(String(init.body))).toEqual({
      signed_request: "sig.payload",
    });
    expect((init.headers as Record<string, string>)["x-spree-api-key"]).toBe(
      "pk-test",
    );
  });

  it("accepts a JSON body too", async () => {
    fetchMock.mockResolvedValue(
      backendResponse({
        url: "/data-deletion-status?code=x",
        confirmation_code: "x",
      }),
    );

    const response = await POST(
      deletionRequest(
        JSON.stringify({ signed_request: "sig.payload" }),
        "application/json",
      ),
    );

    expect(response.status).toBe(200);
    expect(fetchMock).toHaveBeenCalled();
  });

  it("rejects a request without a signed_request", async () => {
    const response = await POST(deletionRequest("other=value"));

    expect(response.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("passes backend verification failures through", async () => {
    fetchMock.mockResolvedValue(
      backendResponse(
        { error: { message: "Invalid signed_request signature" } },
        { ok: false, status: 400 },
      ),
    );

    const response = await POST(deletionRequest("signed_request=forged"));
    const body = (await response.json()) as { error: string };

    expect(response.status).toBe(400);
    expect(body.error).toBe("Invalid signed_request signature");
  });

  it("maps backend outages to a 502", async () => {
    fetchMock.mockRejectedValue(new Error("connection refused"));

    const response = await POST(deletionRequest("signed_request=sig.payload"));

    expect(response.status).toBe(502);
  });
});
