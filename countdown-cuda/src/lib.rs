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
const ERROR_LIST: u32 = 1;
const ERROR_TABLE: u32 = 2;

pub type Answer = (u32, String);

/// Hold the GPU context and loaded kernels which carry nothing from one batch of rounds to the next
pub struct Solver {
    stream: Arc<CudaStream>,
    function: CudaFunction,
    blocks: u32,
    shared: u32,
}

impl Solver {
    /// Load the kernels onto the first GPU and size the launch to fill it
    pub fn new() -> Result<Self, Box<dyn Error>> {
        let ctx = CudaContext::new(0)?;
        let stream = ctx.default_stream();
        let module = ctx.load_module(Ptx::from_binary(KERNELS.to_vec()))?;
        let function = module.load_function("solve")?;
        let size = module.load_function("state_size")?;
        let mut shared = stream.alloc_zeros::<u32>(1)?;
        unsafe { stream.launch_builder(&size).arg(&mut shared).launch(LaunchConfig::for_num_elems(1))? };
        let shared = stream.clone_dtoh(&shared)?[0];
        function.set_attribute(
            CUfunction_attribute_enum::CU_FUNC_ATTRIBUTE_MAX_DYNAMIC_SHARED_SIZE_BYTES,
            shared as i32,
        )?;
        let per_sm = function.occupancy_max_active_blocks_per_multiprocessor(THREADS, shared as usize, None)?;
        let sms = ctx.attribute(CUdevice_attribute_enum::CU_DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT)? as u32;
        Ok(Solver { stream, function, blocks: sms * per_sm.max(1), shared })
    }

    /// Return the value and expression of the answer to every (target, pool) round in order
    pub fn solve_many(&self, rounds: &[(u32, Vec<u32>)]) -> Result<Vec<Answer>, Box<dyn Error>> {
        if let Some((_, pool)) = rounds.iter().find(|(_, p)| p.is_empty() || p.len() > MAX_POOL) {
            return Err(format!("pools must hold one to {MAX_POOL} numbers, not {}", pool.len()).into());
        }
        let mut answers = vec![(0, String::new()); rounds.len()];
        // Solve pools of each size together since the kernel takes one pool size per launch
        for n in 1..=MAX_POOL {
            let indices: Vec<usize> = (0..rounds.len()).filter(|&i| rounds[i].1.len() == n).collect();
            if indices.is_empty() {
                continue;
            }
            let batch: Vec<&(u32, Vec<u32>)> = indices.iter().map(|&i| &rounds[i]).collect();
            for (i, answer) in indices.into_iter().zip(self.solve_batch(n, &batch)?) {
                answers[i] = answer;
            }
        }
        Ok(answers)
    }

    fn solve_batch(&self, n: usize, rounds: &[&(u32, Vec<u32>)]) -> Result<Vec<Answer>, Box<dyn Error>> {
        let mut flat = Vec::with_capacity(rounds.len() * (n + 1));
        for (target, pool) in rounds {
            // Keep every value below the whole pool within the kernel's 24-bit values
            let mut bound: Vec<u64> = pool.iter().map(|&p| u64::from(p).max(2)).collect();
            bound.sort_unstable();
            if bound[1..].iter().product::<u64>() >= VALUE_LIMIT || *target == 0 {
                return Err(format!("round {target} {pool:?} is outside what the kernel can pack").into());
            }
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
        let mut big_tables = unsafe { stream.alloc::<u32>(blocks as usize * BIG_SLOTS)? };
        let mut big_lists = unsafe { stream.alloc::<u32>(blocks as usize * BIG_LIST)? };
        let config = LaunchConfig {
            grid_dim: (blocks, 1, 1),
            block_dim: (THREADS, 1, 1),
            shared_mem_bytes: self.shared,
        };
        let (count32, n32) = (count as u32, n as u32);
        unsafe {
            stream
                .launch_builder(&self.function)
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
