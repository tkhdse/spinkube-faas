use aes::Aes256;
use anyhow::Result;
use ctr::cipher::{KeyIvInit, StreamCipher};
use serde::{Deserialize, Serialize};
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;
use std::hint::black_box;

type Aes256Ctr = ctr::Ctr128BE<Aes256>;

#[derive(Deserialize)]
struct Input {
    message_length: usize,
    num_iterations: u32,
}

#[derive(Serialize)]
struct Output {
    success: bool,
    elapsed_ms: f64,
}

/// Fixed 32-byte key (matches the benchmark's hardcoded key).
const KEY: &[u8; 32] = b"This is a key123This is a key123";
/// Fixed 16-byte nonce/IV.
const NONCE: &[u8; 16] = b"This is an IV456";

fn elapsed_ms(start: std::time::Instant) -> f64 {
    let d = start.elapsed();
    (d.as_secs() as f64) * 1_000.0 + (d.subsec_nanos() as f64) / 1_000_000.0
}

#[http_component]
fn handle(req: Request) -> Result<impl IntoResponse> {
    let input: Input = serde_json::from_slice(req.body())?;
    let start = std::time::Instant::now();

    let mut message = vec![0u8; input.message_length];
    getrandom::getrandom(&mut message).expect("getrandom failed");

    for _ in 0..input.num_iterations {
        let mut ciphertext = message.clone();
        let mut cipher = Aes256Ctr::new(KEY.into(), NONCE.into());
        cipher.apply_keystream(&mut ciphertext);

        let mut decrypted = ciphertext;
        let mut cipher = Aes256Ctr::new(KEY.into(), NONCE.into());
        cipher.apply_keystream(&mut decrypted);

        assert_eq!(black_box(&decrypted), &message);
    }

    let out = Output {
        success: true,
        elapsed_ms: elapsed_ms(start),
    };
    let body = serde_json::to_vec(&out)?;
    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(body)
        .build())
}
