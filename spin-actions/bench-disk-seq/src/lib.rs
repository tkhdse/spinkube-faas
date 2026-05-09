use anyhow::Result;
use serde::{Deserialize, Serialize};
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;
// use std::fs::{self, File};
// use std::io::{Read, Write};

#[derive(Deserialize)]
struct Input {
    byte_size: usize,
    file_size: usize,
}

#[derive(Serialize)]
struct Output {
    write_elapsed_ms: f64,
    read_elapsed_ms: f64,
    total_elapsed_ms: f64,
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
    let total_bytes = input.file_size * 1024 * 1024;
    let block_size = input.byte_size.max(1);
    let mut block = vec![0u8; block_size];
    fill_bytes(&mut block);
    // "Sequential write" into memory buffer
    let write_start = std::time::Instant::now();
    let mut storage = vec![0u8; total_bytes];
    let mut written = 0usize;
    while written < total_bytes {
        let to_write = block_size.min(total_bytes - written);
        storage[written..written + to_write].copy_from_slice(&block[..to_write]);
        written += to_write;
    }
    let write_elapsed_ms = elapsed_ms(write_start);
    // "Sequential read" from memory buffer
    let read_start = std::time::Instant::now();
    let mut total_read = 0usize;
    let mut cursor = 0usize;
    let mut scratch = vec![0u8; block_size];
    while cursor < total_bytes {
        let to_read = block_size.min(total_bytes - cursor);
        scratch[..to_read].copy_from_slice(&storage[cursor..cursor + to_read]);
        total_read += to_read;
        cursor += to_read;
    }
    black_box(total_read);
    let read_elapsed_ms = elapsed_ms(read_start);
    // let _ = fs::remove_file(path);
    let out = Output {
        write_elapsed_ms,
        read_elapsed_ms,
        total_elapsed_ms: write_elapsed_ms + read_elapsed_ms,
    };

    let body = serde_json::to_vec(&out)?;
    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(body)
        .build())
}
