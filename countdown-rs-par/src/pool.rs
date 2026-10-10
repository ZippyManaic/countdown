//! Run a job on every worker of a persistent thread pool that holds no round data between jobs

use std::sync::OnceLock;

/// Return the number of threads to solve each round with, read once from `COUNTDOWN_THREADS`
pub fn threads() -> usize {
    static THREADS: OnceLock<usize> = OnceLock::new();
    *THREADS.get_or_init(|| {
        std::env::var("COUNTDOWN_THREADS")
            .ok()
            .and_then(|t| t.parse().ok())
            .filter(|&t| t >= 1)
            .unwrap_or(8)
    })
}

#[cfg(not(feature = "rayon"))]
mod imp {
    use std::cell::Cell;
    use std::sync::atomic::{AtomicBool, AtomicPtr, AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex, OnceLock};
    use std::thread::Thread;
    use std::time::{Duration, Instant};

    // Keep spinning this long after a job before parking so back-to-back phases skip the futex wake-up
    const SPIN: Duration = Duration::from_micros(500);

    /// Point at the job a dispatch hands to the workers
    struct Job<'a> {
        run: &'a (dyn Fn(usize) + Sync),
    }

    /// Hold the state the dispatching thread shares with the workers
    struct Shared {
        epoch: AtomicUsize,
        job: AtomicPtr<Job<'static>>,
        pending: AtomicUsize,
        sleeping: Vec<AtomicBool>,
    }

    struct Pool {
        shared: Arc<Shared>,
        workers: Vec<Thread>,
        // Let only one thread dispatch at a time since the workers run one job at a time
        busy: Mutex<()>,
    }

    fn pool() -> &'static Pool {
        static POOL: OnceLock<Pool> = OnceLock::new();
        POOL.get_or_init(|| {
            let n = super::threads();
            let shared = Arc::new(Shared {
                epoch: AtomicUsize::new(0),
                job: AtomicPtr::new(std::ptr::null_mut()),
                pending: AtomicUsize::new(0),
                sleeping: (0..n).map(|_| AtomicBool::new(false)).collect(),
            });
            let workers = (1..n)
                .map(|id| {
                    let shared = Arc::clone(&shared);
                    std::thread::Builder::new()
                        .name(format!("solver-{id}"))
                        .spawn(move || work(&shared, id))
                        .expect("worker thread must start")
                        .thread()
                        .clone()
                })
                .collect();
            Pool {
                shared,
                workers,
                busy: Mutex::new(()),
            }
        })
    }

    /// Wait for each new job and run it, spinning briefly before parking
    fn work(shared: &Shared, id: usize) {
        let mut seen = 0;
        loop {
            let start = Instant::now();
            let mut spins = 0u32;
            loop {
                let epoch = shared.epoch.load(Ordering::Acquire);
                if epoch != seen {
                    seen = epoch;
                    break;
                }
                spins += 1;
                if !spins.is_multiple_of(64) || start.elapsed() < SPIN {
                    std::hint::spin_loop();
                    continue;
                }
                // Announce sleep then recheck the epoch so a dispatch cannot slip between the two
                shared.sleeping[id].store(true, Ordering::SeqCst);
                if shared.epoch.load(Ordering::SeqCst) == seen {
                    std::thread::park();
                }
                shared.sleeping[id].store(false, Ordering::SeqCst);
            }
            // SAFETY: the dispatcher keeps the job alive until every worker has decremented pending
            let job = unsafe { &*shared.job.load(Ordering::Acquire) };
            (job.run)(id);
            shared.pending.fetch_sub(1, Ordering::Release);
        }
    }

    thread_local! {
        // Refuse nested dispatch since the pool runs one job at a time
        static INSIDE: Cell<bool> = const { Cell::new(false) };
    }

    /// Call `run` once on each of `threads()` workers with ids from 0 and return when all have finished
    pub fn broadcast(run: &(dyn Fn(usize) + Sync)) {
        let p = pool();
        assert!(!INSIDE.with(Cell::get), "nested broadcast");
        let _guard = p.busy.lock().unwrap_or_else(|e| e.into_inner());
        let job = Job { run };
        // SAFETY: the job outlives the dispatch because this function waits for pending to reach zero
        let ptr = &job as *const Job<'_> as *mut Job<'static>;
        p.shared.job.store(ptr, Ordering::Release);
        p.shared.pending.store(p.workers.len(), Ordering::Relaxed);
        p.shared.epoch.fetch_add(1, Ordering::SeqCst);
        for (id, worker) in p.workers.iter().enumerate() {
            if p.shared.sleeping[id + 1].load(Ordering::SeqCst) {
                worker.unpark();
            }
        }
        INSIDE.with(|i| i.set(true));
        run(0);
        INSIDE.with(|i| i.set(false));
        while p.shared.pending.load(Ordering::Acquire) != 0 {
            std::hint::spin_loop();
        }
    }
}

#[cfg(feature = "rayon")]
mod imp {
    use std::sync::OnceLock;

    fn pool() -> &'static rayon::ThreadPool {
        static POOL: OnceLock<rayon::ThreadPool> = OnceLock::new();
        POOL.get_or_init(|| {
            rayon::ThreadPoolBuilder::new()
                .num_threads(super::threads())
                .build()
                .expect("rayon pool must start")
        })
    }

    /// Call `run` once on each of `threads()` rayon workers and return when all have finished
    pub fn broadcast(run: &(dyn Fn(usize) + Sync)) {
        pool().broadcast(|ctx| run(ctx.index()));
    }
}

pub use imp::broadcast;
