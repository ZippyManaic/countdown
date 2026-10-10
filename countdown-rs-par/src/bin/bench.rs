//! Time the parallel solver over a file of rounds and write each answer as value tab expression

use countdown_par::solve;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let rounds: Vec<Vec<u32>> = std::fs::read_to_string(&args[1])
        .unwrap()
        .lines()
        .map(|l| l.split_whitespace().map(|n| n.parse().unwrap()).collect())
        .collect();
    let reps: usize = args.get(3).map_or(1, |r| r.parse().unwrap());
    let mut out = vec![(0, String::new()); rounds.len()];
    // Start the worker pool before timing so thread creation is not counted
    if countdown_par::threads() > 1 {
        countdown_par::pool::broadcast(&|_| {});
    }
    let start = std::time::Instant::now();
    for _ in 0..reps {
        for (slot, r) in out.iter_mut().zip(&rounds) {
            *slot = solve(r[0], &r[1..]);
        }
    }
    let per_round = start.elapsed().as_secs_f64() * 1000.0 / (rounds.len() * reps) as f64;
    eprintln!("{per_round:.4} ms/round");
    let text: Vec<String> = out.iter().map(|(v, e)| format!("{v}\t{e}")).collect();
    std::fs::write(&args[2], text.join("\n")).unwrap();
}
