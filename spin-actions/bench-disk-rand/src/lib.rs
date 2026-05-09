use anyhow::Result;
use serde::{Deserialize, Serialize};
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;
use std::fs::{self, File, OpenOptions};
// use std::io::{Read, Seek, SeekFrom, Write};

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

/// Tiny deterministic PRNG (no `rand` crate); good enough for seek offsets.
struct Lcg64(u64);

impl Lcg64 {
    fn new() -> Self {
        Lcg64(0x243F_6A88_85A3_08D3)
    }
    fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1);
        self.0
    }
    fn gen_below(&mut self, n: usize) -> usize {
        if n == 0 {
            return 0;
        }
        (self.next_u64() as usize) % n
    }
}

#[http_component]
fn handle(req: Request) -> Result<impl IntoResponse> {
    let input: Input = serde_json::from_slice(req.body())?;
    let total_bytes = input.file_size * 1024 * 1024;
    let block_size = input.byte_size.max(1);
    let num_blocks = (total_bytes / block_size).max(1);
    
    let mut rng = Lcg64::new();
    let mut block = vec![0u8; block_size];
    fill_bytes(&mut block);
    
    // Initialize storage
    let mut storage = vec![0u8; num_blocks * block_size];
    
    // Random write pass
    let write_start = std::time::Instant::now();
    for _ in 0..num_blocks {
        let idx = rng.gen_below(num_blocks);
        let off = idx * block_size;
        storage[off..off + block_size].copy_from_slice(&block);
    }
    let write_elapsed_ms = elapsed_ms(write_start);
    
    // Random read pass
    let read_start = std::time::Instant::now();
    let mut total_read = 0usize;
    let mut scratch = vec![0u8; block_size];
    for _ in 0..num_blocks {
        let idx = rng.gen_below(num_blocks);
        let off = idx * block_size;
        scratch.copy_from_slice(&storage[off..off + block_size]);
        total_read += block_size;
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
