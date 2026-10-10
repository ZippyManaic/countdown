//! Measure how long one empty dispatch to the worker pool takes

fn main() {
    let rounds = 200_000;
    // Start the pool before timing so thread creation is not counted
    countdown_par::pool::broadcast(&|_| {});
    let start = std::time::Instant::now();
    for _ in 0..rounds {
        countdown_par::pool::broadcast(&|_| {});
    }
    let each = start.elapsed().as_secs_f64() * 1e6 / rounds as f64;
    println!("{} threads: {each:.3} us per dispatch", countdown_par::threads());
}
