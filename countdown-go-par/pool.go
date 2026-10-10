package main

import (
	"os"
	"runtime"
	"runtime/debug"
	"strconv"
	"sync"
	"sync/atomic"
)

// job hands out the tasks of one parallel step to whichever workers claim them
type job struct {
	fn    func(worker, task int)
	tasks int32
	// Count claimed tasks so each is run once and finished ones so the caller knows when all are done
	next     atomic.Int32
	finished atomic.Int32
}

// work runs tasks for a worker until none are left to claim
func (j *job) work(worker int) {
	for {
		t := j.next.Add(1) - 1
		if t >= j.tasks {
			return
		}
		j.fn(worker, int(t))
		j.finished.Add(1)
	}
}

// pool runs parallel steps on workers that live for the whole program but hold no round data
type pool struct {
	workers int
	// Bump the generation to tell spinning workers a new job is waiting
	generation atomic.Uint64
	current    atomic.Pointer[job]
}

var (
	thePool  *pool
	poolOnce sync.Once
)

// workerPool returns the shared pool starting its workers the first time it is needed
func workerPool() *pool {
	poolOnce.Do(func() {
		workers := 8
		if n, err := strconv.Atoi(os.Getenv("COUNTDOWN_THREADS")); err == nil && n >= 1 {
			workers = n
		}
		// Give every worker its own processor so spinning never starves the solving goroutine
		runtime.GOMAXPROCS(workers)
		// Collect half as often since workers allocating bitsets mid-collection pay for marking in assists
		if workers > 1 && os.Getenv("GOGC") == "" {
			debug.SetGCPercent(200)
		}
		thePool = &pool{workers: workers}
		for w := 1; w < workers; w++ {
			go thePool.spin(w)
		}
	})
	return thePool
}

// spin waits for each new job by polling the generation and works on it alongside the caller
func (p *pool) spin(worker int) {
	seen := p.generation.Load()
	for spins := 0; ; spins++ {
		g := p.generation.Load()
		if g == seen {
			// Yield now and then so the scheduler and collector can always get in
			if spins&1023 == 1023 {
				runtime.Gosched()
			}
			continue
		}
		seen = g
		p.current.Load().work(worker)
	}
}

// run calls fn for every task from 0 to tasks with the calling goroutine acting as worker 0
func (p *pool) run(tasks int, fn func(worker, task int)) {
	if p.workers == 1 || tasks == 1 {
		for t := range tasks {
			fn(0, t)
		}
		return
	}
	j := &job{fn: fn, tasks: int32(tasks)}
	p.current.Store(j)
	p.generation.Add(1)
	j.work(0)
	// Wait for tasks rather than workers so a late worker never holds up the caller
	for j.finished.Load() != j.tasks {
	}
}
