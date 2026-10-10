//! Generate a Countdown numbers round and solve it with several threads per round

use std::process::ExitCode;

use countdown_par::solve;
use rand::seq::SliceRandom;
use rand::{Rng, RngExt};

const LARGE_NUMBERS: [u32; 4] = [25, 50, 75, 100];

/// Return a random target and a pool of six numbers with either one or two large numbers
fn generate_round(rng: &mut impl Rng) -> (u32, Vec<u32>) {
    let target = rng.random_range(100..=999);
    let large_count = rng.random_range(1..=2);

    // Hold two cards of each small number to match the game's deck
    let mut small: Vec<u32> = (1..=10).chain(1..=10).collect();
    small.shuffle(rng);
    // Shuffle a copy since each large number appears only once in the game
    let mut large = LARGE_NUMBERS.to_vec();
    large.shuffle(rng);

    let mut pool: Vec<u32> = small[..6 - large_count].to_vec();
    pool.extend_from_slice(&large[..large_count]);
    (target, pool)
}

fn main() -> ExitCode {
    let (target, pool) = generate_round(&mut rand::rng());
    let pool_text: Vec<String> = pool.iter().map(u32::to_string).collect();
    println!("Target: {target}");
    println!("Pool:   {}", pool_text.join(" "));

    let (value, expr) = solve(target, &pool);
    if value == target {
        println!("Solved: {expr} = {value}");
        return ExitCode::SUCCESS;
    }
    println!(
        "No exact solution, closest is {expr} = {value} ({} away)",
        value.abs_diff(target)
    );
    ExitCode::FAILURE
}
