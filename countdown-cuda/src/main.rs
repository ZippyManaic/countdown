//! Generate a Countdown numbers round and work out on the GPU whether it can be solved

use std::process::ExitCode;

use rand::seq::SliceRandom;
use rand::{Rng, RngExt};

use countdown_cuda::solve;

const STANDARD_LARGE: [u32; 4] = [25, 50, 75, 100];
// Use the large cards of the 2010 specials for nasty-cats
const NASTY_LARGE: [u32; 4] = [12, 37, 62, 87];
const USAGE: &str = "usage: countdown [standard|cats|nasty] [LARGE]";

/// Name the game mode, which sets the large cards and how many may be dealt
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    Standard,
    Cats,
    Nasty,
}

impl Mode {
    /// Return the four large cards of the mode
    fn large_numbers(self) -> [u32; 4] {
        match self {
            Mode::Nasty => NASTY_LARGE,
            _ => STANDARD_LARGE,
        }
    }

    /// Return the smallest and largest number of large cards the mode allows
    fn large_range(self) -> (usize, usize) {
        match self {
            Mode::Standard => (1, 2),
            _ => (0, 4),
        }
    }
}

/// Return a random target and six numbers with one or two large in standard mode and none to four otherwise
fn generate_round(rng: &mut impl Rng, mode: Mode, large_count: Option<usize>) -> (u32, Vec<u32>) {
    let target = rng.random_range(100..=999);
    let (lo, hi) = mode.large_range();
    let large_count = large_count.unwrap_or_else(|| rng.random_range(lo..=hi));

    // Hold two cards of each small number to match the game's deck
    let mut small: Vec<u32> = (1..=10).chain(1..=10).collect();
    small.shuffle(rng);
    // Shuffle a copy since each large number appears only once in the game
    let mut large = mode.large_numbers().to_vec();
    large.shuffle(rng);

    let mut pool: Vec<u32> = small[..6 - large_count].to_vec();
    pool.extend_from_slice(&large[..large_count]);
    (target, pool)
}

/// Return the mode and fixed large count from the command line, or None when the arguments are invalid
fn parse_args(args: &[String]) -> Option<(Mode, Option<usize>)> {
    if args.len() > 2 {
        return None;
    }
    let mode = match args.first().map(String::as_str) {
        None | Some("standard") => Mode::Standard,
        Some("cats") => Mode::Cats,
        Some("nasty") => Mode::Nasty,
        Some(_) => return None,
    };
    let Some(count) = args.get(1) else {
        return Some((mode, None));
    };
    // Accept only plain digits so that forms such as "+1" are rejected as in the Python version
    if count.len() != 1 || !count.as_bytes()[0].is_ascii_digit() {
        return None;
    }
    let count = usize::from(count.as_bytes()[0] - b'0');
    let (lo, hi) = mode.large_range();
    (lo..=hi).contains(&count).then_some((mode, Some(count)))
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some((mode, large_count)) = parse_args(&args) else {
        eprintln!("{USAGE}");
        return ExitCode::from(2);
    };
    let (target, pool) = generate_round(&mut rand::rng(), mode, large_count);
    let pool_text: Vec<String> = pool.iter().map(u32::to_string).collect();
    println!("Target: {target}");
    println!("Pool:   {}", pool_text.join(" "));

    let (value, expr) = match solve(target, &pool) {
        Ok(answer) => answer,
        Err(e) => {
            eprintln!("countdown: {e}");
            return ExitCode::from(2);
        }
    };
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

#[cfg(test)]
mod tests {
    use super::*;

    /// Return the arguments as owned strings for parse_args
    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    /// Deal many rounds in a mode and check each is legal and every allowed large count occurs
    fn check_deals(mode: Mode) {
        let mut rng = rand::rng();
        let (lo, hi) = mode.large_range();
        let mut seen = [false; 5];
        for _ in 0..2000 {
            let (target, pool) = generate_round(&mut rng, mode, None);
            assert!((100..=999).contains(&target));
            assert_eq!(pool.len(), 6);
            let large: Vec<u32> = pool.iter().copied().filter(|&n| n > 10).collect();
            assert!(large.iter().all(|n| mode.large_numbers().contains(n)));
            for (i, n) in large.iter().enumerate() {
                assert!(!large[i + 1..].contains(n));
            }
            for n in 1..=10 {
                assert!(pool.iter().filter(|&&p| p == n).count() <= 2);
            }
            assert!((lo..=hi).contains(&large.len()));
            seen[large.len()] = true;
        }
        assert!((lo..=hi).all(|count| seen[count]));
    }

    #[test]
    fn deals_valid_pools_in_every_mode() {
        check_deals(Mode::Standard);
        check_deals(Mode::Cats);
        check_deals(Mode::Nasty);
    }

    #[test]
    fn deals_a_fixed_large_count() {
        let mut rng = rand::rng();
        for mode in [Mode::Cats, Mode::Nasty] {
            for count in 0..=4 {
                let (_, pool) = generate_round(&mut rng, mode, Some(count));
                assert_eq!(pool.iter().filter(|&&n| n > 10).count(), count);
            }
        }
    }

    #[test]
    fn parses_valid_arguments() {
        assert_eq!(parse_args(&args(&[])), Some((Mode::Standard, None)));
        assert_eq!(parse_args(&args(&["nasty", "4"])), Some((Mode::Nasty, Some(4))));
        assert_eq!(parse_args(&args(&["cats", "0"])), Some((Mode::Cats, Some(0))));
    }

    #[test]
    fn rejects_invalid_arguments() {
        assert_eq!(parse_args(&args(&["standard", "3"])), None);
        assert_eq!(parse_args(&args(&["cats", "5"])), None);
        assert_eq!(parse_args(&args(&["easy"])), None);
        assert_eq!(parse_args(&args(&["cats", "1", "2"])), None);
        assert_eq!(parse_args(&args(&["cats", "x"])), None);
    }

    #[test]
    fn solves_cats_rounds() {
        assert_eq!(
            solve(100, &[1, 1, 2, 2, 3, 3]).unwrap(),
            (81, "(((2 + 1) * (2 + 1)) * 3) * 3".to_string())
        );
        assert_eq!(
            solve(999, &[2, 3, 87, 62, 37, 12]).unwrap(),
            (999, "37 * ((87 / 3) - 2)".to_string())
        );
    }

    #[test]
    fn solves_pools_that_need_wide_packing() {
        assert_eq!(
            solve(999, &[10, 10, 25, 50, 75, 100]).unwrap(),
            (999, "(((75 + 25) * 100) - 10) / 10".to_string())
        );
    }
}
