// Check every dealable Countdown pool exhaustively by subset reachability, favouring clarity over speed

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

// Use the standard large cards unless another set of four is given on the command line
const LARGE: [u64; 4] = [25, 50, 75, 100];
const LO: u64 = 100;
const HI: u64 = 999;

#[derive(Clone, Copy, PartialEq)]
enum Op {
    Leaf,
    Add,
    Sub,
    Mul,
    Div,
}

// Record how a value was first made: the operator and the two operand masks and values
#[derive(Clone, Copy)]
struct How {
    op: Op,
    left_mask: usize,
    left: u64,
    right_mask: usize,
    right: u64,
}

// List every multiset the dealer can produce, as sorted vectors
fn all_pools(large_counts: &[usize], large_cards: &[u64]) -> Vec<Vec<u64>> {
    let mut out = Vec::new();
    for &large_count in large_counts {
        let small_count = 6 - large_count;
        // Choose the large numbers as a set since there is only one card of each
        let large_sets: Vec<Vec<u64>> = (0..16usize)
            .filter(|bits| bits.count_ones() as usize == large_count)
            .map(|bits| (0..4).filter(|i| bits >> i & 1 == 1).map(|i| large_cards[i]).collect())
            .collect();
        // Count through every vector of copies (0, 1 or 2) of each small number in base 3
        for code in 0..3usize.pow(10) {
            let mut c = code;
            let mut small = Vec::new();
            for number in 1..=10u64 {
                for _ in 0..(c % 3) {
                    small.push(number);
                }
                c /= 3;
            }
            if small.len() != small_count {
                continue;
            }
            for large in &large_sets {
                let mut pool = small.clone();
                pool.extend(large);
                pool.sort();
                out.push(pool);
            }
        }
    }
    out.sort();
    out
}

// Return every legal result of combining a and b in either order, following the paper's operation table
fn combine(a: u64, b: u64) -> Vec<(u64, Op)> {
    let (x, y) = if a >= b { (a, b) } else { (b, a) };
    // Use checked arithmetic so a value too big for 64 bits stops the run instead of wrapping
    let mut out = vec![(x.checked_add(y).expect("sum overflows u64"), Op::Add)];
    if x > y {
        out.push((x - y, Op::Sub));
    }
    if y != 1 {
        out.push((x.checked_mul(y).expect("product overflows u64"), Op::Mul));
        if x % y == 0 {
            out.push((x / y, Op::Div));
        }
    }
    out
}

struct PoolResult {
    line: String,
    certificates: String,
}

fn render(tables: &[BTreeMap<u64, How>], mask: usize, value: u64) -> String {
    let how = tables[mask][&value];
    let (x, xm, y, ym) = if how.left >= how.right {
        (how.left, how.left_mask, how.right, how.right_mask)
    } else {
        (how.right, how.right_mask, how.left, how.left_mask)
    };
    let symbol = match how.op {
        Op::Leaf => return value.to_string(),
        Op::Add => "+",
        Op::Sub => "-",
        Op::Mul => "*",
        Op::Div => "/",
    };
    format!("({} {} {})", render(tables, xm, x), symbol, render(tables, ym, y))
}

fn solve_pool(pool: &[u64]) -> PoolResult {
    let n = pool.len();
    let full = (1usize << n) - 1;
    // Map each subset mask to the values made using exactly that subset and the first way each was made
    let mut tables: Vec<BTreeMap<u64, How>> = vec![BTreeMap::new(); full + 1];
    // Mark targets that some subset makes with a final operation other than multiplication
    let mut non_mul = vec![false; (HI + 1) as usize];
    for mask in 1..=full {
        if mask.count_ones() == 1 {
            let i = mask.trailing_zeros() as usize;
            let how = How { op: Op::Leaf, left_mask: 0, left: 0, right_mask: 0, right: 0 };
            tables[mask].insert(pool[i], how);
            if (LO..=HI).contains(&pool[i]) {
                non_mul[pool[i] as usize] = true;
            }
            continue;
        }
        let mut made: BTreeMap<u64, How> = BTreeMap::new();
        // Try every ordered split into two disjoint non-empty parts, which covers each unordered split twice
        let mut left_mask = (mask - 1) & mask;
        while left_mask != 0 {
            let right_mask = mask ^ left_mask;
            for &a in tables[left_mask].keys() {
                for &b in tables[right_mask].keys() {
                    for (value, op) in combine(a, b) {
                        made.entry(value).or_insert(How { op, left_mask, left: a, right_mask, right: b });
                        if op != Op::Mul && (LO..=HI).contains(&value) {
                            non_mul[value as usize] = true;
                        }
                    }
                }
            }
            left_mask = (left_mask - 1) & mask;
        }
        tables[mask] = made;
    }

    // Take the union over all subsets since not every number has to be used
    let mut union: Vec<u64> = tables.iter().flat_map(|t| t.keys().copied()).collect();
    union.sort();
    union.dedup();
    let largest = *union.last().unwrap();

    let mut misses = String::new();
    let mut mul_only = String::new();
    let mut certificates = String::new();
    let pool_text: Vec<String> = pool.iter().map(|v| v.to_string()).collect();
    writeln!(certificates, "# {}", pool_text.join(" ")).unwrap();
    for t in LO..=HI {
        match union.binary_search(&t) {
            Ok(_) => {
                // Certify with a smallest subset that makes the target, taking the lowest mask among ties
                let mask = (1..=full)
                    .filter(|&m| tables[m].contains_key(&t))
                    .min_by_key(|&m| (m.count_ones(), m))
                    .unwrap();
                writeln!(certificates, "{}\t{}", t, render(&tables, mask, t)).unwrap();
                if !non_mul[t as usize] {
                    if !mul_only.is_empty() {
                        mul_only.push(',');
                    }
                    write!(mul_only, "{}", t).unwrap();
                }
            }
            Err(at) => {
                // Measure the gap to the nearest reachable value on either side
                let below = if at > 0 { t - union[at - 1] } else { u64::MAX };
                let above = if at < union.len() { union[at] - t } else { u64::MAX };
                if !misses.is_empty() {
                    misses.push(',');
                }
                write!(misses, "{}:{}", t, below.min(above)).unwrap();
            }
        }
    }
    let line = format!("{}\t{}\t{}\t{}\t{}", pool_text.join(" "), largest, union.len(), misses, mul_only);
    PoolResult { line, certificates }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 || args.len() > 5 {
        eprintln!("usage: reach RESULTS.tsv THREADS [LARGE_COUNTS, default 1,2] [LARGE_CARDS, default 25,50,75,100] > certificates.txt");
        std::process::exit(2);
    }
    let threads: usize = args[2].parse().expect("THREADS must be a number");
    let large_counts: Vec<usize> = match args.get(3) {
        Some(list) => list.split(',').map(|x| x.parse().expect("LARGE_COUNTS must be numbers")).collect(),
        None => vec![1, 2],
    };
    assert!(large_counts.iter().all(|&l| l <= 4), "at most four large numbers exist");
    let large_cards: Vec<u64> = match args.get(4) {
        Some(list) => list.split(',').map(|x| x.parse().expect("LARGE_CARDS must be numbers")).collect(),
        None => LARGE.to_vec(),
    };
    assert!(large_cards.len() == 4, "give exactly four large cards");
    assert!(large_cards.iter().all(|&c| c > 10), "large cards must differ from the small ones");
    let pools = all_pools(&large_counts, &large_cards);
    eprintln!("{} pools", pools.len());

    // Hand out pools one at a time to worker threads and keep each result in its pool's slot
    let next = AtomicUsize::new(0);
    let results: Mutex<Vec<Option<PoolResult>>> = Mutex::new((0..pools.len()).map(|_| None).collect());
    std::thread::scope(|scope| {
        for _ in 0..threads {
            scope.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                if i >= pools.len() {
                    break;
                }
                let r = solve_pool(&pools[i]);
                results.lock().unwrap()[i] = Some(r);
            });
        }
    });

    let results = results.into_inner().unwrap();
    let mut file = String::from("pool\tmax_value\tdistinct_values\tmisses\tmul_only\n");
    let stdout = std::io::stdout();
    let mut out = std::io::BufWriter::new(stdout.lock());
    for r in results {
        let r = r.unwrap();
        file.push_str(&r.line);
        file.push('\n');
        std::io::Write::write_all(&mut out, r.certificates.as_bytes()).unwrap();
    }
    std::fs::write(&args[1], file).unwrap();
}
