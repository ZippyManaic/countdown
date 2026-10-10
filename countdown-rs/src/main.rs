//! Generate a Countdown numbers round and work out whether it can be solved

use std::process::ExitCode;

use rand::seq::SliceRandom;
use rand::{Rng, RngExt};

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

// Use 32-bit values since no Countdown expression can exceed the product of each pool number plus one
/// Record how a value was made from the larger and smaller of two values in disjoint subsets
#[derive(Clone, Copy)]
struct Origin {
    larger_mask: u8,
    larger: u32,
    smaller_mask: u8,
    smaller: u32,
    op: char,
}

/// Pair a reachable value with how it was made, leaving the origin empty for a pool number
#[derive(Clone, Copy)]
struct Entry {
    value: u32,
    origin: Option<Origin>,
}

/// Pass every legal value from combining two numbers under Countdown rules, with its origin, to emit
fn combine(a: (usize, u32), b: (usize, u32), mut emit: impl FnMut(u32, Origin)) {
    let ((larger_mask, x), (smaller_mask, y)) = if a.1 >= b.1 { (a, b) } else { (b, a) };
    let mut push = |value, op| {
        emit(
            value,
            Origin {
                larger_mask: larger_mask as u8,
                larger: x,
                smaller_mask: smaller_mask as u8,
                smaller: y,
                op,
            },
        )
    };
    push(x + y, '+');
    // Skip a zero result since every intermediate value must be a positive integer
    if x > y {
        push(x - y, '-');
    }
    // Skip multiplying by one as it never produces a new value
    if y != 1 {
        push(x * y, '*');
        if x % y == 0 {
            push(x / y, '/');
        }
    }
}

/// Call visit with every pair of values from each split of a subset into two non-empty halves
fn for_each_split(
    reachable: &[Vec<Entry>],
    mask: usize,
    mut visit: impl FnMut((usize, u32), (usize, u32)),
) {
    let mut left = (mask - 1) & mask;
    while left != 0 {
        let right = mask ^ left;
        // Visit each split once rather than once per ordering
        if left < right {
            for a in &reachable[left] {
                for b in &reachable[right] {
                    visit((left, a.value), (right, b.value));
                }
            }
        }
        left = (left - 1) & mask;
    }
}

/// Return every number that combines with n under Countdown rules to make the target, with its operator
fn partners(n: u32, target: u32) -> impl Iterator<Item = (u32, char)> {
    [
        (target.checked_sub(n), '+'),
        (n.checked_sub(target), '-'),
        (n.checked_add(target), '-'),
        (
            target
                .is_multiple_of(n)
                .then(|| target / n)
                .filter(|&m| n.min(m) != 1),
            '*',
        ),
        (
            n.is_multiple_of(target)
                .then(|| n / target)
                .filter(|&m| m != 1),
            '/',
        ),
        (n.checked_mul(target).filter(|_| n != 1), '/'),
    ]
    .into_iter()
    .filter_map(|(m, op)| m.filter(|&m| m > 0).map(|m| (m, op)))
}

/// Return the position of an operator in the order combine yields them
fn op_rank(op: char) -> u8 {
    match op {
        '+' => 0,
        '-' => 1,
        '*' => 2,
        _ => 3,
    }
}

/// Return how the target is first made from a subset without building all of its values
fn find_exact(reachable: &[Vec<Entry>], mask: usize, target: u32) -> Option<Entry> {
    let contains = |values: &[Entry], v: u32| values.binary_search_by_key(&v, |e| e.value).is_ok();
    let mut left = (mask - 1) & mask;
    while left != 0 {
        let right = mask ^ left;
        // Visit splits in the same order as for_each_split so the same origin wins
        if left < right {
            let (lefts, rights) = (&reachable[left], &reachable[right]);
            // Loop over the smaller half and binary search the larger for the earliest pair combine would yield
            let hit = if lefts.len() <= rights.len() {
                lefts.iter().find_map(|a| {
                    partners(a.value, target)
                        .filter(|&(b, _)| contains(rights, b))
                        .min_by_key(|&(b, op)| (b, op_rank(op)))
                        .map(|(b, op)| (a.value, b, op))
                })
            } else {
                rights
                    .iter()
                    .flat_map(|b| {
                        partners(b.value, target)
                            .filter(|&(a, _)| contains(lefts, a))
                            .map(move |(a, op)| (a, b.value, op))
                    })
                    .min_by_key(|&(a, b, op)| (a, b, op_rank(op)))
            };
            if let Some((a, b, op)) = hit {
                let ((larger_mask, larger), (smaller_mask, smaller)) = if a >= b {
                    ((left, a), (right, b))
                } else {
                    ((right, b), (left, a))
                };
                let origin = Origin {
                    larger_mask: larger_mask as u8,
                    larger,
                    smaller_mask: smaller_mask as u8,
                    smaller,
                    op,
                };
                return Some(Entry {
                    value: target,
                    origin: Some(origin),
                });
            }
        }
        left = (left - 1) & mask;
    }
    None
}

/// Rebuild the expression for a reachable value by following its origins back to the pool
fn render(reachable: &[Vec<Entry>], entry: &Entry) -> String {
    let lookup = |mask: u8, value| {
        let values = &reachable[mask as usize];
        let index = values
            .binary_search_by_key(&value, |e| e.value)
            .expect("value must be reachable from its subset");
        render(reachable, &values[index])
    };
    match entry.origin {
        None => entry.value.to_string(),
        Some(o) => format!(
            "({} {} {})",
            lookup(o.larger_mask, o.larger),
            o.op,
            lookup(o.smaller_mask, o.smaller)
        ),
    }
}

/// Return the simplest expression that hits the target or gets closest to it, with its value
fn solve(target: u32, pool: &[u32]) -> (u32, String) {
    // Map each subset of the pool (as a bitmask) to its reachable values sorted ascending with one origin each
    let mut reachable: Vec<Vec<Entry>> = vec![Vec::new(); 1 << pool.len()];
    let full = reachable.len() - 1;
    let mut candidates = Vec::new();
    let mut exact = None;
    // Bound each subset's values by the product of its numbers plus one, as Proposition prop:bound shows
    let bound = |mask: usize| -> u64 {
        (0..pool.len()).filter(|i| mask >> i & 1 == 1).map(|i| u64::from(pool[i]) + 1).product()
    };
    let mut seen: Vec<u64> = Vec::new();

    // Work through subsets smallest first so the search can stop at the first size that hits the target
    let size_masks = |size| (1..=full).filter(move |m: &usize| m.count_ones() == size);
    for size in 1..=pool.len() as u32 {
        if size == 1 {
            for mask in size_masks(1) {
                let value = pool[mask.trailing_zeros() as usize];
                reachable[mask] = vec![Entry {
                    value,
                    origin: None,
                }];
            }
            exact = size_masks(1)
                .map(|mask| reachable[mask][0])
                .find(|e| e.value == target);
        } else {
            // Keep the lowest matching subset of this size to break ties the same way every run
            exact = size_masks(size).find_map(|mask| find_exact(&reachable, mask, target));
        }
        // Skip building the values of the whole pool since no larger subset is made from them
        if exact.is_some() || size == pool.len() as u32 {
            break;
        }
        if size == 1 {
            continue;
        }
        // Grow the bitset only as far as this size needs since most rounds stop before the largest subsets
        let words = size_masks(size).map(bound).max().unwrap_or(0).div_ceil(64) as usize;
        if words > seen.len() {
            seen.resize(words, 0);
        }
        for mask in size_masks(size) {
            candidates.clear();
            // Keep only the first way found to make each value so duplicates never reach the sort
            for_each_split(&reachable, mask, |a, b| {
                combine(a, b, |value, origin| {
                    let (word, bit) = (value as usize / 64, 1 << (value % 64));
                    if seen[word] & bit == 0 {
                        seen[word] |= bit;
                        candidates.push(Entry {
                            value,
                            origin: Some(origin),
                        });
                    }
                });
            });
            // Clear only the bits this subset set so the bitset is ready for the next one
            for e in &candidates {
                seen[e.value as usize / 64] = 0;
            }
            candidates.sort_unstable_by_key(|e| e.value);
            reachable[mask] = candidates.clone();
        }
    }

    let best = match exact {
        Some(entry) => entry,
        None => {
            // Check the whole pool's values as they are made since no larger subset is built from them
            let mut whole: Option<Entry> = None;
            if full.is_power_of_two() {
                whole = Some(Entry {
                    value: pool[0],
                    origin: None,
                });
            } else {
                for_each_split(&reachable, full, |a, b| {
                    combine(a, b, |value, origin| {
                        // Prefer the lower value on equal distance to break ties the same way every run
                        if whole.is_none_or(|w| {
                            (value.abs_diff(target), value) < (w.value.abs_diff(target), w.value)
                        }) {
                            whole = Some(Entry {
                                value,
                                origin: Some(origin),
                            });
                        }
                    });
                });
            }

            // Rank by distance from the target then by how many numbers are used so the simplest answer wins
            let distance = |e: &Entry| e.value.abs_diff(target);
            let partial = reachable
                .iter()
                .enumerate()
                .flat_map(|(mask, values)| values.iter().map(move |e| (mask.count_ones(), e)))
                .min_by_key(|&(used, e)| (distance(e), used))
                .map(|(_, e)| *e);
            // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
            match (partial, whole) {
                (Some(p), Some(w)) if distance(&w) < distance(&p) => w,
                (Some(p), _) => p,
                (None, w) => w.expect("pool must not be empty"),
            }
        }
    };

    let expr = render(&reachable, &best);
    // Strip the redundant outermost brackets for display
    let expr = match expr.strip_prefix('(').and_then(|e| e.strip_suffix(')')) {
        Some(inner) => inner.to_string(),
        None => expr,
    };
    (best.value, expr)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_simplest_solution() {
        assert_eq!(
            solve(125, &[1, 5, 7, 3, 75, 50]),
            (125, "75 + 50".to_string())
        );
        assert_eq!(solve(552, &[8, 4, 2, 5, 100, 25]).0, 552);
    }

    #[test]
    fn reports_closest_when_unsolvable() {
        let (value, _) = solve(974, &[8, 8, 6, 8, 25, 100]);
        assert_eq!(value.abs_diff(974), 1);
    }

    #[test]
    fn reports_a_lone_number_as_closest() {
        assert_eq!(solve(100, &[7]), (7, "7".to_string()));
    }

    #[test]
    fn solves_with_a_lone_number() {
        assert_eq!(solve(7, &[7]), (7, "7".to_string()));
    }

    #[test]
    fn reports_closest_with_two_numbers() {
        assert_eq!(solve(100, &[3, 4]), (12, "4 * 3".to_string()));
    }

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
            solve(999, &[10, 10, 25, 50, 75, 100]),
            (999, "(((75 + 25) * 100) - 10) / 10".to_string())
        );
        assert_eq!(
            solve(100, &[1, 1, 2, 2, 3, 3]),
            (81, "(((2 + 1) * (2 + 1)) * 3) * 3".to_string())
        );
        assert_eq!(
            solve(999, &[2, 3, 87, 62, 37, 12]),
            (999, "37 * ((87 / 3) - 2)".to_string())
        );
    }
}
