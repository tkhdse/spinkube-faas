use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;

#[derive(Deserialize)]
struct Input {
    json_string: String,
}

#[derive(Serialize)]
struct Output {
    parsed: Value,
    serialized_length: usize,
    elapsed_ms: f64,
}

fn elapsed_ms(start: std::time::Instant) -> f64 {
    let d = start.elapsed();
    (d.as_secs() as f64) * 1_000.0 + (d.subsec_nanos() as f64) / 1_000_000.0
}

#[inline]
fn black_box<T>(dummy: T) -> T {
    // Keep benchmark logic from being optimized away.
    unsafe {
        let ret = std::ptr::read_volatile(&dummy as *const T);
        std::mem::forget(dummy);
        ret
    }
}

#[http_component]
fn handle(req: Request) -> Result<impl IntoResponse> {
    let input: Input = serde_json::from_slice(req.body())?;
    let start = std::time::Instant::now();
    let parsed: Value = serde_json::from_str(&input.json_string)?;
    let serialized = serde_json::to_string(&parsed)?;
    let serialized_length = black_box(serialized.len());
    let out = Output {
        parsed,
        serialized_length,
        elapsed_ms: elapsed_ms(start),
    };

    let body = serde_json::to_vec(&out)?;
    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(body)
        .build())
}
