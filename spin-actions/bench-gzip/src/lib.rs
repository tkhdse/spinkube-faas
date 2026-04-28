use anyhow::Result;
use flate2::Compression;
use flate2::write::GzEncoder;
use serde::{Deserialize, Serialize};
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;
use std::io::Write;

#[derive(Deserialize)]
struct Input {
    file_size: usize,
}

#[derive(Serialize)]
struct Output {
    original_size: usize,
    compressed_size: usize,
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

fn fill_bytes(buf: &mut [u8]) {
    for (i, b) in buf.iter_mut().enumerate() {
        let i = i as u32;
        *b = ((i.wrapping_mul(131) ^ 0xA5) % 256) as u8;
    }
}

#[http_component]
fn handle(req: Request) -> Result<impl IntoResponse> {
    let input: Input = serde_json::from_slice(req.body())?;
    let size_bytes = input.file_size * 1024 * 1024;

    let mut data = vec![0u8; size_bytes];
    fill_bytes(&mut data);

    let start = std::time::Instant::now();
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(&data)?;
    let compressed = encoder.finish()?;
    let compressed_size = black_box(compressed.len());

    let out = Output {
        original_size: size_bytes,
        compressed_size,
        elapsed_ms: elapsed_ms(start),
    };

    let body = serde_json::to_vec(&out)?;
    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(body)
        .build())
}
