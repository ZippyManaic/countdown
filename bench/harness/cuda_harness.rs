// Time the GPU solver over a file of rounds solved as one batch and write each answer as value tab expression
use countdown_cuda::Solver;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let rounds: Vec<(u32, Vec<u32>)> = std::fs::read_to_string(&args[1])
        .unwrap()
        .lines()
        .map(|l| {
            let n: Vec<u32> = l.split_whitespace().map(|n| n.parse().unwrap()).collect();
            (n[0], n[1..].to_vec())
        })
        .collect();
    let reps: usize = args.get(3).map_or(1, |r| r.parse().unwrap());
    let solver = Solver::new().unwrap();
    // Warm up untimed for a second so loading the kernels is excluded and the GPU has raised its clock
    let warm = std::time::Instant::now();
    while warm.elapsed().as_secs_f64() < 1.0 {
        solver.solve_many(&rounds).unwrap();
    }
    let mut out = Vec::new();
    let start = std::time::Instant::now();
    for _ in 0..reps {
        out = solver.solve_many(&rounds).unwrap();
    }
    let per_round = start.elapsed().as_secs_f64() * 1000.0 / (rounds.len() * reps) as f64;
    eprintln!("{per_round:.6} ms/round");
    let text: Vec<String> = out.iter().map(|(v, e)| format!("{v}\t{e}")).collect();
    std::fs::write(&args[2], text.join("\n")).unwrap();
}
