use anyhow::Result;
use serde::{Deserialize, Serialize};
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;

#[derive(Deserialize)]
struct Input {
    n: u64,
}

#[derive(Serialize)]
struct Output {
    result: f64,
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

fn float_ops(n: u64) -> f64 {
    let mut result = 0.0_f64;
    for i in 0..n {
        let x = i as f64;
        result += (x.sin() * x.cos()).abs().sqrt();
    }
    result
}

#[http_component]
fn handle(req: Request) -> Result<impl IntoResponse> {
    let input: Input = serde_json::from_slice(req.body())?;
    let start = std::time::Instant::now();
    let result = black_box(float_ops(input.n));
    let out = Output {
        result,
        elapsed_ms: elapsed_ms(start),
    };

    let body = serde_json::to_vec(&out)?;
    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(body)
        .build())
}
