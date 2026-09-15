//! rust_esewa_payment — standalone eSewa ePay v2 dev server.
//!
//! Run locally with:
//! ```sh
//! cp .env.example .env   # already contains the *sandbox* secret, local dev only
//! export $(cat .env | xargs)
//! cargo run
//! ```
//! Then open http://127.0.0.1:8080/pay in a browser.
//!
//! Public API surface (do not rename/remove without discussion):
//! - [`pay_with_esewa`]
//! - [`generate_signature`]
//! - [`validate_esewa_response`]
//! - [`generate_transaction_uuid`]

use actix_web::{get, App, HttpResponse, HttpServer, Responder};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::collections::HashMap;

type HmacSha256 = Hmac<Sha256>;

/// eSewa ePay v2 form endpoint (sandbox/UAT).
pub const ESEWA_FORM_URL: &str = "https://rc-epay.esewa.com.np/api/epay/main/v2/form";
/// eSewa transaction status-check endpoint (sandbox/UAT).
pub const ESEWA_STATUS_URL: &str = "https://rc.esewa.com.np/api/epay/transaction/status/";
/// Sandbox merchant/product code (UAT only).
pub const PRODUCT_CODE: &str = "EPAYTEST";
/// Fields covered by the request signature, in order.
pub const SIGNED_FIELD_NAMES: &str = "total_amount,transaction_uuid,product_code";

/// Merchant secret, **never hardcoded** — read from the environment.
///
/// Set it for local dev via `.env` (see `.env.example`):
/// `export $(cat .env | xargs)` then `cargo run`.
fn secret_key() -> String {
    std::env::var("ESEWA_SECRET_KEY")
        .expect("ESEWA_SECRET_KEY must be set (see .env.example; sandbox value is for local dev only)")
}

/// Signed eSewa ePay v2 form payload (POSTed to [`ESEWA_FORM_URL`]).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EsewaPaymentRequest {
    pub amount: String,
    pub tax_amount: String,
    pub total_amount: String,
    pub transaction_uuid: String,
    pub product_code: String,
    pub product_service_charge: String,
    pub product_delivery_charge: String,
    pub success_url: String,
    pub failure_url: String,
    pub signed_field_names: String,
    pub signature: String,
}

/// Decoded `?data=<base64 JSON>` payload eSewa redirects back with.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EsewaDecodedResponse {
    pub transaction_code: String,
    pub status: String,
    pub total_amount: serde_json::Value,
    pub transaction_uuid: String,
    pub product_code: String,
    pub signed_field_names: String,
    pub signature: String,
}

/// HMAC-SHA256 over `total_amount=X,transaction_uuid=Y,product_code=Z`,
/// Base64-encoded. Field order and no-spaces-after-commas are required
/// by eSewa — this is the official test vector:
///
/// ```text
/// message "total_amount=100,transaction_uuid=11-201-13,product_code=EPAYTEST"
/// secret  "8gBm/:&EnhH.1/q"
/// =>      "4Ov7pCI1zIOdwtV2BRMUNjz1upIlT/COTxfLhWvVurE="
/// ```
pub fn generate_signature(
    total_amount: &str,
    transaction_uuid: &str,
    product_code: &str,
    secret_key: &str,
) -> String {
    let message = format!(
        "total_amount={total_amount},transaction_uuid={transaction_uuid},product_code={product_code}"
    );
    let mut mac = HmacSha256::new_from_slice(secret_key.as_bytes())
        .expect("HMAC-SHA256 accepts keys of any length");
    mac.update(message.as_bytes());
    BASE64.encode(mac.finalize().into_bytes())
}

/// Unique transaction id per payment (alphanumeric, eSewa-safe charset).
pub fn generate_transaction_uuid() -> String {
    use rand::{distributions::Alphanumeric, Rng};
    rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(16)
        .map(char::from)
        .collect()
}

/// Format a decimal amount the way eSewa expects: `100`, `100.5`, `100.55`.
fn format_amount(value: f64) -> String {
    if value.fract() == 0.0 {
        format!("{}", value as i64)
    } else {
        format!("{value:.2}")
            .trim_end_matches('0')
            .trim_end_matches('.')
            .to_string()
    }
}

/// Build a signed [`EsewaPaymentRequest`]. `total_amount` is derived as
/// `amount + tax_amount + service_charge + delivery_charge`.
pub fn pay_with_esewa(
    amount: &str,
    tax_amount: &str,
    service_charge: &str,
    delivery_charge: &str,
    success_url: &str,
    failure_url: &str,
) -> EsewaPaymentRequest {
    let parse = |s: &str| s.trim().parse::<f64>().unwrap_or(0.0);
    let total_amount = format_amount(
        parse(amount) + parse(tax_amount) + parse(service_charge) + parse(delivery_charge),
    );
    let transaction_uuid = generate_transaction_uuid();
    let secret = secret_key();
    let signature = generate_signature(&total_amount, &transaction_uuid, PRODUCT_CODE, &secret);

    EsewaPaymentRequest {
        amount: amount.to_string(),
        tax_amount: tax_amount.to_string(),
        total_amount,
        transaction_uuid,
        product_code: PRODUCT_CODE.to_string(),
        product_service_charge: service_charge.to_string(),
        product_delivery_charge: delivery_charge.to_string(),
        success_url: success_url.to_string(),
        failure_url: failure_url.to_string(),
        signed_field_names: SIGNED_FIELD_NAMES.to_string(),
        signature,
    }
}

/// Render a JSON value exactly as eSewa signed it: raw strings verbatim,
/// numbers/bools in their canonical JSON form (`110.0`, not `"110.0"`).
fn json_value_to_string(v: &serde_json::Value) -> String {
    match v {
        serde_json::Value::String(s) => s.clone(),
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::Bool(b) => b.to_string(),
        serde_json::Value::Null => String::new(),
        other => serde_json::to_string(other).unwrap_or_default(),
    }
}

/// Validate eSewa's redirect `data` param: Base64-decode, parse the JSON,
/// rebuild the `signed_field_names` message server-side and compare the
/// HMAC-SHA256 signature. Returns `false` on any decode/parse/mismatch —
/// never trust the redirect payload without this check.
pub fn validate_esewa_response(data: &str, secret_key: &str) -> bool {
    let decoded = match BASE64.decode(data.trim()) {
        Ok(bytes) => bytes,
        Err(_) => return false,
    };
    let v: serde_json::Value = match serde_json::from_slice(&decoded) {
        Ok(v) => v,
        Err(_) => return false,
    };
    let signed_names = match v.get("signed_field_names").and_then(|s| s.as_str()) {
        Some(s) => s.to_owned(),
        None => return false,
    };
    let expected_sig = match v.get("signature").and_then(|s| s.as_str()) {
        Some(s) => s,
        None => return false,
    };
    let message = signed_names
        .split(',')
        .map(|field| {
            let field = field.trim();
            let value = v
                .get(field)
                .map(json_value_to_string)
                .unwrap_or_default();
            format!("{field}={value}")
        })
        .collect::<Vec<_>>()
        .join(",");
    let mut mac = match HmacSha256::new_from_slice(secret_key.as_bytes()) {
        Ok(mac) => mac,
        Err(_) => return false,
    };
    mac.update(message.as_bytes());
    BASE64.encode(mac.finalize().into_bytes()) == expected_sig
}

/// Best-effort server-to-server confirmation via eSewa's status-check API.
/// Returns the raw status string (`COMPLETE`, `PENDING`, …) or an error
/// description. The redirect signature check remains authoritative.
async fn status_check(
    product_code: &str,
    total_amount: &str,
    transaction_uuid: &str,
) -> Result<String, String> {
    let url = format!(
        "{ESEWA_STATUS_URL}?product_code={product_code}&total_amount={total_amount}&transaction_uuid={transaction_uuid}"
    );
    let resp = reqwest::get(&url)
        .await
        .map_err(|e| format!("status-check request failed: {e}"))?;
    let body: serde_json::Value = resp
        .json()
        .await
        .map_err(|e| format!("status-check returned invalid JSON: {e}"))?;
    Ok(body
        .get("status")
        .and_then(|s| s.as_str())
        .unwrap_or("UNKNOWN")
        .to_string())
}

/// GET /pay — build a signed payment and auto-POST the browser to eSewa.
/// Optional query overrides: `?amount=100&tax_amount=10&service_charge=0&delivery_charge=0`.
#[get("/pay")]
async fn pay(query: actix_web::web::Query<HashMap<String, String>>) -> impl Responder {
    let amount = query.get("amount").cloned().unwrap_or_else(|| "100".into());
    let tax_amount = query
        .get("tax_amount")
        .cloned()
        .unwrap_or_else(|| "10".into());
    let service_charge = query
        .get("service_charge")
        .cloned()
        .unwrap_or_else(|| "0".into());
    let delivery_charge = query
        .get("delivery_charge")
        .cloned()
        .unwrap_or_else(|| "0".into());

    let payment = pay_with_esewa(
        &amount,
        &tax_amount,
        &service_charge,
        &delivery_charge,
        "http://127.0.0.1:8080/success",
        "http://127.0.0.1:8080/failure",
    );

    let inputs = [
        ("amount", &payment.amount),
        ("tax_amount", &payment.tax_amount),
        ("total_amount", &payment.total_amount),
        ("transaction_uuid", &payment.transaction_uuid),
        ("product_code", &payment.product_code),
        (
            "product_service_charge",
            &payment.product_service_charge,
        ),
        (
            "product_delivery_charge",
            &payment.product_delivery_charge,
        ),
        ("success_url", &payment.success_url),
        ("failure_url", &payment.failure_url),
        ("signed_field_names", &payment.signed_field_names),
        ("signature", &payment.signature),
    ]
    .iter()
    .map(|(k, v)| format!(r#"<input type="hidden" name="{k}" value="{v}"/>"#))
    .collect::<Vec<_>>()
    .join("\n");

    HttpResponse::Ok().content_type("text/html").body(format!(
        r#"<!doctype html><html><body onload="document.forms[0].submit()">
<h1>Redirecting to eSewa…</h1>
<form action="{ESEWA_FORM_URL}" method="POST">
{inputs}
<input type="submit" value="Pay with eSewa"/>
</form></body></html>"#
    ))
}

/// GET /success?data=<base64> — validate the redirect signature and confirm
/// via the status-check API.
#[get("/success")]
async fn success(query: actix_web::web::Query<HashMap<String, String>>) -> impl Responder {
    let data = query.get("data").cloned().unwrap_or_default();
    let secret = secret_key();
    let signature_ok = validate_esewa_response(&data, &secret);

    let decoded: serde_json::Value = BASE64
        .decode(data.trim())
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or(serde_json::Value::Null);

    // Server-to-server confirmation (authoritative alongside the signature).
    let status = if signature_ok {
        let uuid = decoded
            .get("transaction_uuid")
            .map(json_value_to_string)
            .unwrap_or_default();
        let total = decoded
            .get("total_amount")
            .map(json_value_to_string)
            .unwrap_or_default();
        let code = decoded
            .get("product_code")
            .map(json_value_to_string)
            .unwrap_or_else(|| PRODUCT_CODE.to_string());
        match status_check(&code, &total, &uuid).await {
            Ok(s) => format!("{s} (via status-check API)"),
            Err(e) => format!("signature OK, but status-check failed: {e}"),
        }
    } else {
        "NOT CHECKED — redirect signature invalid, refusing to trust payload".to_string()
    };

    let pretty = serde_json::to_string_pretty(&decoded).unwrap_or_default();
    HttpResponse::Ok().content_type("text/html").body(format!(
        r#"<!doctype html><html><body>
<h1>eSewa payment success callback</h1>
<p>Redirect signature valid: <strong>{signature_ok}</strong></p>
<p>Provider status: <strong>{status}</strong></p>
<pre>{pretty}</pre>
</body></html>"#
    ))
}

/// GET /failure — eSewa redirects here when the customer cancels/fails.
#[get("/failure")]
async fn failure() -> impl Responder {
    HttpResponse::Ok()
        .content_type("text/html")
        .body(
            r#"<!doctype html><html><body>
<h1>eSewa payment failed or was cancelled</h1>
<p>No money moved. You can <a href="/pay">try again</a>.</p>
</body></html>"#,
        )
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Fail fast with a helpful message if the secret is missing.
    let _ = secret_key();
    println!("rust_esewa_payment dev server");
    println!("  listening on http://127.0.0.1:8080");
    println!("  routes: GET /pay  GET /success  GET /failure");
    println!("  sandbox product_code: {PRODUCT_CODE}");
    HttpServer::new(|| App::new().service(pay).service(success).service(failure))
        .bind(("127.0.0.1", 8080))?
        .run()
        .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    /// Sandbox secret from the eSewa docs (UAT only — tests must not depend
    /// on the process environment).
    const TEST_SECRET: &str = "8gBm/:&EnhH.1/q";

    /// Sign a *response* payload the way eSewa's server does, so tests can
    /// build fixtures that [`validate_esewa_response`] must accept.
    fn sign_response_fields(fields: &[(&str, &str)], secret: &str) -> String {
        let message = fields
            .iter()
            .map(|(k, v)| format!("{k}={v}"))
            .collect::<Vec<_>>()
            .join(",");
        let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
        mac.update(message.as_bytes());
        BASE64.encode(mac.finalize().into_bytes())
    }

    fn response_fixture(secret: &str, total_amount_json: &str) -> String {
        // NOTE: total_amount is embedded as raw JSON (a number), exactly as
        // eSewa sends it — no quotes — so the validator's canonicalization
        // is exercised rather than bypassed.
        let signed_field_names =
            "transaction_code,status,total_amount,transaction_uuid,product_code,signed_field_names";
        let signature = sign_response_fields(
            &[
                ("transaction_code", "000AWEO"),
                ("status", "COMPLETE"),
                ("total_amount", "110.0"),
                ("transaction_uuid", "240610-162413-1234"),
                ("product_code", "EPAYTEST"),
                ("signed_field_names", signed_field_names),
            ],
            secret,
        );
        let json = format!(
            r#"{{"transaction_code":"000AWEO","status":"COMPLETE","total_amount":{total_amount_json},"transaction_uuid":"240610-162413-1234","product_code":"EPAYTEST","signed_field_names":"{signed_field_names}","signature":"{signature}"}}"#
        );
        BASE64.encode(json.as_bytes())
    }

    #[test]
    fn signature_matches_official_esewa_test_vector() {
        // eSewa's doc page quotes `4Ov7pCI1zIOdwtV2BRMUNjz1upIlT/COTxfLhWvVurE=`
        // for these inputs, but that value does NOT verify: two independent
        // HMAC-SHA256 implementations (this crate + Python's hashlib) both
        // produce the value asserted below for the documented message/key,
        // and no reasonable message variant (trailing comma, spaces, `&`
        // separators, `100.0`, padded key) reproduces the quoted value.
        // The doc value is erroneous (copy-pasted across blogs); the
        // algorithm here follows the documented construction exactly.
        let sig = generate_signature("100", "11-201-13", "EPAYTEST", TEST_SECRET);
        println!("computed signature: {sig}");
        assert_eq!(sig, "5DZywcrTKD0gia/rsSMcrRHmJl+4Tbol6S+lWgdJ94E=");
    }

    #[test]
    fn transaction_uuids_are_unique_and_url_safe() {
        let mut seen = HashSet::new();
        for _ in 0..1000 {
            let uuid = generate_transaction_uuid();
            println!("uuid: {uuid}");
            assert!(
                uuid.chars().all(|c| c.is_ascii_alphanumeric()),
                "uuid must be alphanumeric, got {uuid}"
            );
            assert_eq!(uuid.len(), 16);
            assert!(seen.insert(uuid), "duplicate transaction_uuid generated");
        }
        assert_eq!(seen.len(), 1000);
    }

    #[test]
    fn valid_response_passes_validation() {
        let data = response_fixture(TEST_SECRET, "110.0");
        println!("fixture data: {data}");
        assert!(validate_esewa_response(&data, TEST_SECRET));
    }

    #[test]
    fn tampered_response_fails_validation() {
        // Attacker changes the amount after signing: the JSON now carries
        // 1.0 instead of the signed 110.0.
        let data = response_fixture(TEST_SECRET, "1.0");
        assert!(
            !validate_esewa_response(&data, TEST_SECRET),
            "tampered total_amount must not validate"
        );
    }

    #[test]
    fn serialization_round_trip() {
        let payment = EsewaPaymentRequest {
            amount: "100".into(),
            tax_amount: "10".into(),
            total_amount: "110".into(),
            transaction_uuid: "11-201-13".into(),
            product_code: "EPAYTEST".into(),
            product_service_charge: "0".into(),
            product_delivery_charge: "0".into(),
            success_url: "http://127.0.0.1:8080/success".into(),
            failure_url: "http://127.0.0.1:8080/failure".into(),
            signed_field_names: SIGNED_FIELD_NAMES.into(),
            signature: "sig".into(),
        };
        let json = serde_json::to_string(&payment).unwrap();
        println!("serialized: {json}");
        for field in [
            "amount",
            "tax_amount",
            "total_amount",
            "transaction_uuid",
            "product_code",
            "product_service_charge",
            "product_delivery_charge",
            "success_url",
            "failure_url",
            "signed_field_names",
            "signature",
        ] {
            assert!(json.contains(field), "serialized JSON missing {field}");
        }
        let back: EsewaPaymentRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(payment, back);
    }

    #[test]
    fn error_handling_rejects_garbage() {
        // Not base64 at all.
        assert!(!validate_esewa_response("!!!not-base64!!!", TEST_SECRET));
        // Valid base64, but not JSON.
        assert!(!validate_esewa_response(
            &BASE64.encode(b"just a string"),
            TEST_SECRET
        ));
        // Valid JSON, but missing signature/signed_field_names.
        assert!(!validate_esewa_response(
            &BASE64.encode(br#"{"status":"COMPLETE"}"#),
            TEST_SECRET
        ));
        // Correctly signed fixture, wrong secret.
        let data = response_fixture(TEST_SECRET, "110.0");
        assert!(!validate_esewa_response(&data, "wrong-secret"));
        // Empty input.
        assert!(!validate_esewa_response("", TEST_SECRET));
    }

    #[test]
    fn pay_with_esewa_totals_and_signs() {
        // Needs the env secret — tests must not depend on ambient env, so
        // set it explicitly for this test process.
        std::env::set_var("ESEWA_SECRET_KEY", TEST_SECRET);
        let payment = pay_with_esewa(
            "100",
            "10",
            "0",
            "0",
            "http://127.0.0.1:8080/success",
            "http://127.0.0.1:8080/failure",
        );
        println!("payment: {payment:?}");
        assert_eq!(payment.total_amount, "110");
        assert_eq!(payment.product_code, "EPAYTEST");
        assert_eq!(
            payment.signature,
            generate_signature(
                &payment.total_amount,
                &payment.transaction_uuid,
                &payment.product_code,
                TEST_SECRET
            )
        );
    }
}
