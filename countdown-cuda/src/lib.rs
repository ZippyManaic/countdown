//! Solve Countdown numbers rounds on an NVIDIA GPU with one thread block working on each round

use std::error::Error;
use std::sync::Arc;

use cudarc::driver::sys::{CUdevice_attribute_enum, CUfunction_attribute_enum};
use cudarc::driver::{CudaContext, CudaFunction, CudaStream, LaunchConfig, PushKernelArg};
use cudarc::nvrtc::Ptx;

const KERNELS: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/solver.fatbin"));
const THREADS: u32 = 512;
const TEXT: usize = 64;
const MAX_POOL: usize = 6;
const BIG_SLOTS: usize = 16384;
const BIG_LIST: usize = 20480;
const VALUE_LIMIT: u64 = 1 << 24;
const WIDE_LIMIT: u64 = 1 << 27;
const ERROR_LIST: u32 = 1;
const ERROR_TABLE: u32 = 2;

pub type Answer = (u32, String);

/// Name the two ways the kernel packs a round's values
#[derive(Clone, Copy, PartialEq, Eq)]
enum Packing {
    Narrow,
    Wide,
}

/// Return the packing a round needs from the bounds on its stored subsets' values or None when neither fits
fn packing(pool: &[u32]) -> Option<Packing> {
    let mut bound: Vec<u64> = pool.iter().map(|&p| u64::from(p).max(2)).collect();
    bound.sort_unstable();
    let n = bound.len();
    // Bound the shared-memory subsets in 24 bits as those up to two smaller than the pool or single numbers
    let small: u64 = bound[n - (n.max(3) - 2)..].iter().product();
    let below: u64 = bound[1..].iter().product();
    if small >= VALUE_LIMIT || below >= WIDE_LIMIT {
        None
    } else if below < VALUE_LIMIT {
        Some(Packing::Narrow)
    } else {
        Some(Packing::Wide)
    }
}

/// Hold the GPU context and loaded kernels which carry nothing from one batch of rounds to the next
pub struct Solver {
    stream: Arc<CudaStream>,
    narrow: CudaFunction,
    wide: CudaFunction,
    blocks: u32,
    shared: u32,
}

impl Solver {
    /// Load the kernels onto the first GPU and size the launch to fill it
    pub fn new() -> Result<Self, Box<dyn Error>> {
        let ctx = CudaContext::new(0)?;
        let stream = ctx.default_stream();
        let module = ctx.load_module(Ptx::from_binary(KERNELS.to_vec()))?;
        let narrow = module.load_function("solve")?;
        let wide = module.load_function("solve_wide")?;
        let size = module.load_function("state_size")?;
        let mut shared = stream.alloc_zeros::<u32>(1)?;
        unsafe { stream.launch_builder(&size).arg(&mut shared).launch(LaunchConfig::for_num_elems(1))? };
        let shared = stream.clone_dtoh(&shared)?[0];
        for function in [&narrow, &wide] {
            function.set_attribute(
                CUfunction_attribute_enum::CU_FUNC_ATTRIBUTE_MAX_DYNAMIC_SHARED_SIZE_BYTES,
                shared as i32,
            )?;
        }
        // Size both launches by the narrow kernel since the two share its state and launch bounds
        let per_sm = narrow.occupancy_max_active_blocks_per_multiprocessor(THREADS, shared as usize, None)?;
        let sms = ctx.attribute(CUdevice_attribute_enum::CU_DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT)? as u32;
        Ok(Solver { stream, narrow, wide, blocks: sms * per_sm.max(1), shared })
    }

    /// Return the value and expression of the answer to every (target, pool) round in order
    pub fn solve_many(&self, rounds: &[(u32, Vec<u32>)]) -> Result<Vec<Answer>, Box<dyn Error>> {
        if let Some((_, pool)) = rounds.iter().find(|(_, p)| p.is_empty() || p.len() > MAX_POOL) {
            return Err(format!("pools must hold one to {MAX_POOL} numbers, not {}", pool.len()).into());
        }
        let mut packings = Vec::with_capacity(rounds.len());
        for (target, pool) in rounds {
            match packing(pool) {
                Some(p) if *target != 0 => packings.push(p),
                _ => return Err(format!("round {target} {pool:?} is outside what the kernel can pack").into()),
            }
        }
        let mut answers = vec![(0, String::new()); rounds.len()];
        // Solve pools of each size and packing together since the kernel takes one of each per launch
        for n in 1..=MAX_POOL {
            for packing in [Packing::Narrow, Packing::Wide] {
                let indices: Vec<usize> =
                    (0..rounds.len()).filter(|&i| rounds[i].1.len() == n && packings[i] == packing).collect();
                if indices.is_empty() {
                    continue;
                }
                let batch: Vec<&(u32, Vec<u32>)> = indices.iter().map(|&i| &rounds[i]).collect();
                let solved = match packing {
                    Packing::Narrow => self.solve_batch::<u32>(&self.narrow, n, &batch)?,
                    Packing::Wide => self.solve_batch::<u64>(&self.wide, n, &batch)?,
                };
                for (i, answer) in indices.into_iter().zip(solved) {
                    answers[i] = answer;
                }
            }
        }
        Ok(answers)
    }

    /// Solve rounds of one pool size with a kernel whose global tables hold keys of type K
    fn solve_batch<K: cudarc::driver::DeviceRepr + cudarc::driver::ValidAsZeroBits>(
        &self,
        function: &CudaFunction,
        n: usize,
        rounds: &[&(u32, Vec<u32>)],
    ) -> Result<Vec<Answer>, Box<dyn Error>> {
        let mut flat = Vec::with_capacity(rounds.len() * (n + 1));
        for (target, pool) in rounds {
            flat.push(*target);
            flat.extend_from_slice(pool);
        }
        let count = rounds.len();
        let stream = &self.stream;
        let input = stream.clone_htod(&flat)?;
        // Leave the outputs unset since the kernel writes every round's value and text
        let mut values = unsafe { stream.alloc::<u32>(count)? };
        let mut text = unsafe { stream.alloc::<u8>(count * TEXT)? };
        let mut next = stream.alloc_zeros::<u32>(1)?;
        let mut errors = stream.alloc_zeros::<u32>(1)?;
        let blocks = self.blocks.min(count as u32);
        // Give each block global room for the rare rounds that need subsets one smaller than the pool
        let mut big_tables = unsafe { stream.alloc::<K>(blocks as usize * BIG_SLOTS)? };
        let mut big_lists = unsafe { stream.alloc::<K>(blocks as usize * BIG_LIST)? };
        let config = LaunchConfig {
            grid_dim: (blocks, 1, 1),
            block_dim: (THREADS, 1, 1),
            shared_mem_bytes: self.shared,
        };
        let (count32, n32) = (count as u32, n as u32);
        unsafe {
            stream
                .launch_builder(function)
                .arg(&input)
                .arg(&count32)
                .arg(&n32)
                .arg(&mut values)
                .arg(&mut text)
                .arg(&mut next)
                .arg(&mut big_tables)
                .arg(&mut big_lists)
                .arg(&mut errors)
                .launch(config)?;
        }
        let errors = stream.clone_dtoh(&errors)?[0];
        if errors != 0 {
            let what = match errors {
                e if e & ERROR_LIST != 0 => "value lists",
                e if e & ERROR_TABLE != 0 => "hash tables",
                _ => "queue of partner checks",
            };
            return Err(format!("a round overflowed the kernel's {what}").into());
        }
        let values = stream.clone_dtoh(&values)?;
        let text = stream.clone_dtoh(&text)?;
        Ok(values
            .into_iter()
            .zip(text.as_chunks::<TEXT>().0)
            .map(|(value, chars)| {
                let end = chars.iter().position(|&c| c == 0).unwrap_or(TEXT);
                (value, String::from_utf8(chars[..end].to_vec()).expect("the kernel writes ASCII text"))
            })
            .collect())
    }
}

/// Return the simplest expression that hits the target or gets closest to it, with its value
pub fn solve(target: u32, pool: &[u32]) -> Result<Answer, Box<dyn Error>> {
    Ok(Solver::new()?.solve_many(&[(target, pool.to_vec())])?.remove(0))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rounds(name: &str) -> Vec<(u32, Vec<u32>)> {
        std::fs::read_to_string(format!("../bench/data/{name}"))
            .unwrap()
            .lines()
            .map(|l| {
                let n: Vec<u32> = l.split_whitespace().map(|n| n.parse().unwrap()).collect();
                (n[0], n[1..].to_vec())
            })
            .collect()
    }

    #[test]
    fn finds_simplest_solution() {
        assert_eq!(solve(125, &[1, 5, 7, 3, 75, 50]).unwrap(), (125, "75 + 50".to_string()));
        assert_eq!(solve(100, &[1, 2, 3, 4, 5, 100]).unwrap(), (100, "100".to_string()));
    }

    #[test]
    fn reports_closest_when_unsolvable() {
        let (value, _) = solve(974, &[8, 8, 6, 8, 25, 100]).unwrap();
        assert_eq!(value.abs_diff(974), 1);
    }

    #[test]
    fn handles_smaller_pools() {
        let solver = Solver::new().unwrap();
        let answers = solver.solve_many(&[(7, vec![3, 4]), (12, vec![2, 3, 2]), (25, vec![5])]).unwrap();
        assert_eq!(answers[0], (7, "4 + 3".to_string()));
        assert_eq!(answers[1].0, 12);
        assert_eq!(answers[2], (5, "5".to_string()));
    }

    #[test]
    fn mixes_narrow_and_wide_rounds() {
        let solver = Solver::new().unwrap();
        let rounds = [(999, vec![10, 10, 25, 50, 75, 100]), (125, vec![1, 5, 7, 3, 75, 50])];
        let answers = solver.solve_many(&rounds).unwrap();
        assert_eq!(answers[0], (999, "(((75 + 25) * 100) - 10) / 10".to_string()));
        assert_eq!(answers[1], (125, "75 + 50".to_string()));
    }

    #[test]
    fn refuses_pools_no_mode_deals_beyond_the_packing() {
        assert!(solve(999, &[1000, 1000, 1000, 1000, 1000, 1000]).is_err());
        assert!(solve(999, &[20_000_000]).is_err());
    }

    #[test]
    fn matches_reference_answers() {
        let solver = Solver::new().unwrap();
        let expected = std::fs::read_to_string("../bench/data/ref10k.tsv").unwrap();
        let got: Vec<String> = solver
            .solve_many(&rounds("rounds10k.txt"))
            .unwrap()
            .into_iter()
            .map(|(v, e)| format!("{v}\t{e}"))
            .collect();
        assert_eq!(got, expected.trim_end().lines().collect::<Vec<_>>());
    }
}
