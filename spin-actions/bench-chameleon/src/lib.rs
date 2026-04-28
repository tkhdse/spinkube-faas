use anyhow::Result;
use serde::{Deserialize, Serialize};
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;

#[derive(Deserialize)]
struct Input {
    num_of_cols: usize,
    num_of_rows: usize,
}

#[derive(Serialize)]
struct Output {
    html_length: usize,
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

fn render_table(rows: usize, cols: usize) -> String {
    let mut html = String::with_capacity(rows * cols * 40);
    html.push_str("<table>\n");
    for r in 0..rows {
        html.push_str("  <tr>\n");
        for c in 0..cols {
            html.push_str("    <td>");
            if c % 2 == 0 {
                html.push_str(&format!("Row {}, Col {}", r, c));
            } else {
                html.push_str(&format!("{}", r * cols + c));
            }
            html.push_str("</td>\n");
        }
        html.push_str("  </tr>\n");
    }
    html.push_str("</table>");
    html
}

#[http_component]
fn handle(req: Request) -> Result<impl IntoResponse> {
    // Expect JSON body: {"num_of_cols":100,"num_of_rows":100}
    let input: Input = serde_json::from_slice(req.body())?;

    let start = std::time::Instant::now();
    let html = render_table(input.num_of_rows, input.num_of_cols);
    let html_length = black_box(html.len());

    let out = Output {
        html_length,
        elapsed_ms: elapsed_ms(start),
    };

    let body = serde_json::to_vec(&out)?;
    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(body)
        .build())
}