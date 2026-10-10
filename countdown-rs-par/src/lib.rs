//! Solve Countdown numbers rounds with the reference algorithm, spreading each round's larger levels over several threads

#[doc(hidden)]
pub mod pool;

use std::cell::UnsafeCell;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicUsize, Ordering};

pub use pool::threads;

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

/// Share a value between threads that promise to touch it from one thread at a time
struct Shared<T>(UnsafeCell<T>);

// SAFETY: every phase writes each cell from one worker and reads it only after the phase's barrier
unsafe impl<T: Send> Sync for Shared<T> {}

impl<T> Shared<T> {
    fn new(value: T) -> Self {
        Self(UnsafeCell::new(value))
    }

    /// Return a shared reference to the value, which is sound only while no thread writes the cell
    #[allow(clippy::mut_from_ref)]
    unsafe fn get(&self) -> &T {
        unsafe { &*self.0.get() }
    }

    /// Return an exclusive reference to the value, which is sound only while no other thread touches the cell
    #[allow(clippy::mut_from_ref)]
    unsafe fn get_mut(&self) -> &mut T {
        unsafe { &mut *self.0.get() }
    }
}

/// Hold every subset's reachable values where workers can fill different subsets at once
struct Table(Vec<Shared<Vec<Entry>>>);

impl Table {
    /// Return the sorted values of a subset that is fully built
    fn values(&self, mask: usize) -> &[Entry] {
        // SAFETY: a subset is only read once the phase that built it has finished
        unsafe { self.0[mask].get() }
    }

    /// Store the sorted values of a subset that no other worker is building
    fn set(&self, mask: usize, values: Vec<Entry>) {
        // SAFETY: each subset is built by exactly one worker and nobody reads it during that phase
        unsafe { *self.0[mask].get_mut() = values }
    }
}

/// Read a tuning threshold once from the environment, falling back to its default
fn tuned(name: &str, default: usize, cell: &'static OnceLock<usize>) -> usize {
    *cell.get_or_init(|| std::env::var(name).ok().and_then(|v| v.parse().ok()).unwrap_or(default))
}

/// Return the least work, in values scanned, worth spreading a search over the pool
fn search_threshold() -> usize {
    static CELL: OnceLock<usize> = OnceLock::new();
    tuned("COUNTDOWN_PAR_SEARCH", 1500, &CELL)
}

/// Return the least work, in pairs combined, worth spreading a build or whole-pool pass over the pool
fn build_threshold() -> usize {
    static CELL: OnceLock<usize> = OnceLock::new();
    tuned("COUNTDOWN_PAR_BUILD", 400, &CELL)
}

/// Return the pairs each chunk of the whole-pool pass covers
fn chunk_pairs() -> usize {
    static CELL: OnceLock<usize> = OnceLock::new();
    tuned("COUNTDOWN_PAR_CHUNK", 2048, &CELL)
}

/// Pass every legal value from combining two numbers under Countdown rules, with its origin, to emit
#[inline(always)]
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
        if x.is_multiple_of(y) {
            push(x / y, '/');
        }
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

/// Return the first way building would make the target from one split as left value, right value and operator
fn split_hit(table: &Table, left: usize, right: usize, target: u32) -> Option<(u32, u32, char)> {
    let contains = |values: &[Entry], v: u32| values.binary_search_by_key(&v, |e| e.value).is_ok();
    let (lefts, rights) = (table.values(left), table.values(right));
    // Loop over the smaller half and binary search the larger for the earliest pair combine would yield
    if lefts.len() <= rights.len() {
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
    }
}

/// Turn a split's hit into an entry for the target with the larger operand first
fn hit_entry(left: usize, right: usize, (a, b, op): (u32, u32, char), target: u32) -> Entry {
    let ((larger_mask, larger), (smaller_mask, smaller)) = if a >= b {
        ((left, a), (right, b))
    } else {
        ((right, b), (left, a))
    };
    Entry {
        value: target,
        origin: Some(Origin {
            larger_mask: larger_mask as u8,
            larger,
            smaller_mask: smaller_mask as u8,
            smaller,
            op,
        }),
    }
}

/// Rebuild the expression for a reachable value by following its origins back to the pool
fn render(table: &Table, entry: &Entry) -> String {
    let lookup = |mask: u8, value| {
        let values = table.values(mask as usize);
        let index = values
            .binary_search_by_key(&value, |e| e.value)
            .expect("value must be reachable from its subset");
        render(table, &values[index])
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

/// List each split of a subset as (left, right) in the order the reference visits them
fn splits_of(mask: usize) -> impl Iterator<Item = (usize, usize)> {
    let mut left = (mask - 1) & mask;
    std::iter::from_fn(move || {
        while left != 0 {
            let l = left;
            left = (left - 1) & mask;
            // Visit each split once rather than once per ordering
            if l < (mask ^ l) {
                return Some((l, mask ^ l));
            }
        }
        None
    })
}

/// Hold one round's working state shared by the threads solving it
struct Round {
    target: u32,
    table: Table,
    // Bound every subset's values so each worker's bitset covers exactly what a level can make
    max: Vec<u64>,
    // Give each worker its own bitset of values seen in the subset it is building
    seen: Vec<Shared<Vec<u64>>>,
    threads: usize,
}

impl Round {
    /// Return the first way the target is made from any subset of this size, lowest mask and earliest split first
    fn search(&self, masks: &[usize]) -> Option<Entry> {
        let items: Vec<(usize, usize)> = masks.iter().flat_map(|&m| splits_of(m)).collect();
        let work: usize = items
            .iter()
            .map(|&(l, r)| self.table.values(l).len().min(self.table.values(r).len()))
            .sum();
        if self.threads == 1 || work < search_threshold() {
            return items.iter().find_map(|&(l, r)| {
                split_hit(&self.table, l, r, self.target).map(|h| hit_entry(l, r, h, self.target))
            });
        }
        // Hand out splits in canonical order and keep the earliest hit since that is the one the reference finds
        let next = AtomicUsize::new(0);
        let best = AtomicUsize::new(usize::MAX);
        let hits: Vec<Shared<Option<(u32, u32, char)>>> = items.iter().map(|_| Shared::new(None)).collect();
        pool::broadcast(&|_| {
            loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                if i >= items.len() || i > best.load(Ordering::Relaxed) {
                    break;
                }
                let (l, r) = items[i];
                if let Some(h) = split_hit(&self.table, l, r, self.target) {
                    // SAFETY: only the worker that took item i writes its slot
                    unsafe { *hits[i].get_mut() = Some(h) };
                    best.fetch_min(i, Ordering::Relaxed);
                }
            }
        });
        let i = best.into_inner();
        (i != usize::MAX).then(|| {
            let (l, r) = items[i];
            // SAFETY: the broadcast has returned so every write is visible and finished
            let h = unsafe { hits[i].get() }.expect("best item must hold a hit");
            hit_entry(l, r, h, self.target)
        })
    }

    /// Build one subset's sorted values keeping only the first way found to make each
    fn build_one(&self, mask: usize, seen: &mut Vec<u64>, candidates: &mut Vec<Entry>) {
        let words = (self.max[mask] / 64 + 1) as usize;
        if seen.len() < words {
            seen.resize(words, 0);
        }
        candidates.clear();
        for (left, right) in splits_of(mask) {
            for a in self.table.values(left) {
                for b in self.table.values(right) {
                    combine((left, a.value), (right, b.value), |value, origin| {
                        let (word, bit) = (value as usize / 64, 1u64 << (value % 64));
                        if seen[word] & bit == 0 {
                            seen[word] |= bit;
                            candidates.push(Entry {
                                value,
                                origin: Some(origin),
                            });
                        }
                    });
                }
            }
        }
        // Clear only the bits this subset set so the bitset is ready for the next one
        for e in candidates.iter() {
            seen[e.value as usize / 64] = 0;
        }
        candidates.sort_unstable_by_key(|e| e.value);
        self.table.set(mask, candidates.clone());
    }

    /// Build every subset of this size, spreading the subsets over the pool when there is enough work
    fn build(&self, masks: &[usize]) {
        let pairs = |m: usize| -> usize {
            splits_of(m)
                .map(|(l, r)| self.table.values(l).len() * self.table.values(r).len())
                .sum()
        };
        let mut items: Vec<(usize, usize)> = masks.iter().map(|&m| (pairs(m), m)).collect();
        let work: usize = items.iter().map(|&(p, _)| p).sum();
        if self.threads == 1 || work < build_threshold() || items.len() == 1 {
            // SAFETY: only this thread is running
            let seen = unsafe { self.seen[0].get_mut() };
            let mut candidates = Vec::new();
            for &m in masks {
                self.build_one(m, seen, &mut candidates);
            }
            return;
        }
        // Hand out the biggest subsets first so the last ones to finish are small
        items.sort_unstable_by_key(|&(p, _)| std::cmp::Reverse(p));
        let next = AtomicUsize::new(0);
        pool::broadcast(&|id| {
            // SAFETY: each worker owns the bitset at its id
            let seen = unsafe { self.seen[id].get_mut() };
            let mut candidates = Vec::new();
            loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                let Some(&(_, m)) = items.get(i) else { break };
                self.build_one(m, seen, &mut candidates);
            }
        });
    }

    /// Return the whole pool's closest value as made first, comparing distance then value
    fn whole(&self, full: usize) -> Option<Entry> {
        // Cut each split into runs of left values so big splits spread over the pool while keeping canonical order
        let chunk = chunk_pairs();
        let mut items = Vec::new();
        let mut work = 0;
        for (l, r) in splits_of(full) {
            let (nl, nr) = (self.table.values(l).len(), self.table.values(r).len());
            work += nl * nr;
            let step = (chunk / nr.max(1)).max(1);
            let mut start = 0;
            while start < nl {
                items.push((l, r, start, (start + step).min(nl)));
                start += step;
            }
        }
        let target = self.target;
        // Keep the first value strictly closer, or as close and lower, within the items one worker scans in order
        let scan = |item: &(usize, usize, usize, usize), best: &mut Option<Entry>| {
            let &(l, r, from, to) = item;
            for a in &self.table.values(l)[from..to] {
                for b in self.table.values(r) {
                    combine((l, a.value), (r, b.value), |value, origin| {
                        if best.is_none_or(|w| {
                            (value.abs_diff(target), value) < (w.value.abs_diff(target), w.value)
                        }) {
                            *best = Some(Entry {
                                value,
                                origin: Some(origin),
                            });
                        }
                    });
                }
            }
        };
        if self.threads == 1 || work < build_threshold() {
            let mut best = None;
            items.iter().for_each(|it| scan(it, &mut best));
            return best;
        }
        let next = AtomicUsize::new(0);
        // Record each worker's best with the item it came from so ties go to the earliest item
        let bests: Vec<Shared<Option<(Entry, usize)>>> = (0..self.threads).map(|_| Shared::new(None)).collect();
        pool::broadcast(&|id| {
            let mut best: Option<Entry> = None;
            let mut from_item = usize::MAX;
            loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                let Some(item) = items.get(i) else { break };
                let before = best.map(|e| e.value);
                scan(item, &mut best);
                // Workers take items in increasing order so a change here means this item holds the first better value
                if best.map(|e| e.value) != before {
                    from_item = i;
                }
            }
            // SAFETY: each worker writes only its own slot
            unsafe { *bests[id].get_mut() = best.map(|e| (e, from_item)) };
        });
        bests
            .iter()
            // SAFETY: the broadcast has returned so every slot is final
            .filter_map(|b| unsafe { *b.get() })
            .min_by_key(|&(e, item)| (e.value.abs_diff(target), e.value, item))
            .map(|(e, _)| e)
    }
}

/// Return the simplest expression that hits the target or gets closest to it, with its value
pub fn solve(target: u32, pool: &[u32]) -> (u32, String) {
    let n = pool.len();
    assert!((1..=8).contains(&n), "pool must hold one to eight numbers");
    let full = (1usize << n) - 1;
    let threads = threads();
    let mut round = Round {
        target,
        table: Table((0..=full).map(|_| Shared::new(Vec::new())).collect()),
        max: vec![0; full + 1],
        seen: (0..threads).map(|_| Shared::new(Vec::new())).collect(),
        threads,
    };

    // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    for mask in 1..=full {
        round.max[mask] = if mask.is_power_of_two() {
            u64::from(pool[mask.trailing_zeros() as usize])
        } else {
            splits_of(mask)
                .map(|(l, r)| {
                    let (a, b) = (round.max[l], round.max[r]);
                    (a * b).max(a + b)
                })
                .max()
                .unwrap_or(0)
        };
    }
    let round = round;

    // List subsets by size then mask so each level is one slice
    let mut by_size: Vec<Vec<usize>> = vec![Vec::new(); n + 1];
    for mask in 1..=full {
        by_size[mask.count_ones() as usize].push(mask);
    }

    // Work through subsets smallest first so the search can stop at the first size that hits the target
    let mut exact = None;
    for size in 1..=n {
        if size == 1 {
            for &mask in &by_size[1] {
                round.table.set(
                    mask,
                    vec![Entry {
                        value: pool[mask.trailing_zeros() as usize],
                        origin: None,
                    }],
                );
            }
            exact = by_size[1]
                .iter()
                .map(|&mask| round.table.values(mask)[0])
                .find(|e| e.value == target);
        } else {
            // Keep the lowest matching subset of this size to break ties the same way every run
            exact = round.search(&by_size[size]);
        }
        // Skip building the values of the whole pool since no larger subset is made from them
        if exact.is_some() || size == n {
            break;
        }
        if size > 1 {
            round.build(&by_size[size]);
        }
    }

    let best = match exact {
        Some(entry) => entry,
        None => {
            // Check the whole pool's values as they are made since no larger subset is built from them
            let whole = if full.is_power_of_two() {
                Some(Entry {
                    value: pool[0],
                    origin: None,
                })
            } else {
                round.whole(full)
            };

            // Rank by distance from the target then by how many numbers are used so the simplest answer wins
            let distance = |e: &Entry| e.value.abs_diff(target);
            let partial = (1..full)
                .flat_map(|mask| {
                    round
                        .table
                        .values(mask)
                        .iter()
                        .map(move |e| (mask.count_ones(), e))
                })
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

    let expr = render(&round.table, &best);
    // Strip the redundant outermost brackets for display
    let expr = match expr.strip_prefix('(').and_then(|e| e.strip_suffix(')')) {
        Some(inner) => inner.to_string(),
        None => expr,
    };
    (best.value, expr)
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

    #[test]
    fn handles_smaller_pools() {
        assert_eq!(solve(10, &[3, 4]), (12, "4 * 3".to_string()));
        assert_eq!(solve(7, &[5]), (5, "5".to_string()));
    }
}
