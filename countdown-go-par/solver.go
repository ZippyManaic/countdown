package main

import (
	"math"
	"math/bits"
	"strconv"
	"strings"
	"sync/atomic"
	"unsafe"
)

// rankMin is the value count below which a subset is insertion sorted rather than ranked in the bitset
const rankMin = 16

// buildMin is the fewest pairs a size must combine before its subsets are built in parallel
const buildMin = 2000

// searchMin is the fewest values a size's searches must scan before its subsets are searched in parallel
const searchMin = 100

// closestMin is the fewest pairs the whole pool must combine before its splits are checked in parallel
const closestMin = 2000

// entry records a reachable value with how it was made from the larger and smaller of two values in disjoint subsets
type entry struct {
	// Pack value, operator (zero for a pool number), larger mask and smaller mask from the low bits up
	head uint64
	// Pack the larger operand in the low half and the smaller in the high half
	operands uint64
}

func (e entry) value() uint32      { return uint32(e.head) }
func (e entry) op() byte           { return byte(e.head >> 32) }
func (e entry) largerMask() uint8  { return uint8(e.head >> 40) }
func (e entry) smallerMask() uint8 { return uint8(e.head >> 48) }
func (e entry) larger() uint32     { return uint32(e.operands) }
func (e entry) smaller() uint32    { return uint32(e.operands >> 32) }

// template returns the operator and masks of an entry shifted above its value
func template(op byte, largerMask, smallerMask uint) uint64 {
	return uint64(uint(op)|largerMask<<8|smallerMask<<16) << 32
}

// templates returns the four operator templates for a split with the given larger and smaller halves
func templates(largerMask, smallerMask uint) [4]uint64 {
	return [4]uint64{
		template('+', largerMask, smallerMask), template('-', largerMask, smallerMask),
		template('*', largerMask, smallerMask), template('/', largerMask, smallerMask),
	}
}

// quotient returns x divided by y rounded to the nearest integer using the reciprocal of y
func quotient(x uint32, inv float64) uint32 {
	return uint32(float64(x)*inv + 0.5)
}

// exact returns q when q times y is x and zero otherwise using a mask since Go would branch on the comparison
func exact(q, y, x uint32) uint32 {
	// Turn a zero difference into an all-ones mask and anything else into zero
	return q & uint32((uint64(q*y^x)-1)>>32)
}

// scratch holds one worker's working memory for one solve
type scratch struct {
	// Hold one bit per value seen in the subset being built
	seen []uint64
	// Hold the count of values below each bitset word for ranking
	rank []uint32
	// Collect a subset's new values here before they are sorted out
	tmp []entry
	// Keep the sorted values of every subset this worker built back to back
	arena []entry
	// Hold the right half's values with their reciprocals for the split being worked on
	rightValues []uint32
	rightInv    []float64
}

// state holds the working memory of one solve shared by every worker
type state struct {
	target uint32
	full   uint
	// Point at each subset's sorted values wherever the worker that built it keeps them
	vals [256][]entry
	// Hold the largest value each subset can make which bounds the bitset words it touches
	max [256]uint32
	// Give each worker its own scratch so building needs no locks
	work []scratch
	// Size the right-half buffers for the largest subset built so far
	rightsMax int
}

// grow returns a slice of at least need entries holding the first keep entries of old by doubling its length
func grow(old []entry, keep, need int) []entry {
	if need <= len(old) {
		return old
	}
	size := max(len(old), 1024)
	for size < need {
		size *= 2
	}
	grown := make([]entry, size)
	copy(grown, old[:keep])
	return grown
}

// ready makes a worker's bitset hold at least words words and its right-half buffers big enough
func (s *state) ready(w *scratch, words int) {
	// Replace rather than copy since building leaves the bitset clear
	if words > len(w.seen) {
		w.seen = make([]uint64, words)
		w.rank = make([]uint32, words)
	}
	s.readyRights(w)
}

// readyRights makes a worker's right-half buffers big enough for the largest subset built so far
func (s *state) readyRights(w *scratch) {
	if s.rightsMax > len(w.rightValues) {
		w.rightValues = make([]uint32, s.rightsMax)
		w.rightInv = make([]float64, s.rightsMax)
	}
}

// loadRights copies a half's values next to their reciprocals so each divisor is inverted once per split
func (s *state) loadRights(w *scratch, right uint) ([]uint32, []float64) {
	rights := s.vals[right]
	rv := w.rightValues[:len(rights)]
	ri := w.rightInv[:len(rights)]
	for j, e := range rights {
		rv[j] = e.value()
		ri[j] = 1 / float64(rv[j])
	}
	return rv, ri
}

// emit stores a value at out advancing past it only if the bitset shows it is new so duplicates cost no mispredicted branch
func emit(seen unsafe.Pointer, out unsafe.Pointer, v uint32, head, operands uint64) unsafe.Pointer {
	// Skip bounds checks since the bitset covers the subset's largest value and build reserved room for every store
	word := (*uint64)(unsafe.Add(seen, uintptr(v>>6)*8))
	x := *word
	*word = x | 1<<(v&63)
	*(*entry)(out) = entry{head | uint64(v), operands}
	return unsafe.Add(out, uintptr(^x>>(v&63)&1)*unsafe.Sizeof(entry{}))
}

// emitSplit appends every new value from combining the two halves of a split at k and returns the new count
func (s *state) emitSplit(w *scratch, left, right uint, k int) int {
	seen, out := unsafe.Pointer(&w.seen[0]), unsafe.Pointer(&w.tmp[k])
	tl, tr := templates(left, right), templates(right, left)
	rv, ri := s.loadRights(w, right)
	for _, l := range s.vals[left] {
		a := l.value()
		j := 0
		// Pair with right values up to a first where a is the larger and ties go left
		for ; j < len(rv) && rv[j] <= a; j++ {
			b := rv[j]
			operands := uint64(a) | uint64(b)<<32
			out = emit(seen, out, a+b, tl[0], operands)
			// Skip a zero result since every intermediate value must be a positive integer
			if a != b {
				out = emit(seen, out, a-b, tl[1], operands)
			}
			// Skip multiplying and dividing by one as they never produce a new value
			if b != 1 {
				out = emit(seen, out, a*b, tl[2], operands)
				// Emit zero for an inexact division since bit 0 stays set so it is dropped
				q := exact(quotient(a, ri[j]), b, a)
				out = emit(seen, out, q, tl[3], operands)
			}
		}
		// Pair with the remaining larger right values where a is the smaller
		ia := 1 / float64(a)
		for ; j < len(rv); j++ {
			b := rv[j]
			operands := uint64(b) | uint64(a)<<32
			out = emit(seen, out, b+a, tr[0], operands)
			out = emit(seen, out, b-a, tr[1], operands)
			if a != 1 {
				out = emit(seen, out, b*a, tr[2], operands)
				q := exact(quotient(b, ia), a, b)
				out = emit(seen, out, q, tr[3], operands)
			}
		}
	}
	return k + int((uintptr(out)-uintptr(unsafe.Pointer(&w.tmp[k])))/unsafe.Sizeof(entry{}))
}

// checker keeps the whole pool's value closest to the target preferring the lower value on equal distance
type checker struct {
	target   uint32
	distance uint32
	best     entry
}

func (c *checker) check(v uint32, head, operands uint64) {
	d := distance(v, c.target)
	if v != 0 && (d < c.distance || (d == c.distance && v < c.best.value())) {
		c.distance = d
		c.best = entry{head | uint64(v), operands}
	}
}

// checkSplit checks every value from combining the two halves of a split of the whole pool
func (s *state) checkSplit(w *scratch, c *checker, left, right uint) {
	tl, tr := templates(left, right), templates(right, left)
	rv, ri := s.loadRights(w, right)
	for _, l := range s.vals[left] {
		a := l.value()
		j := 0
		// Pair with right values up to a first where a is the larger and ties go left
		for ; j < len(rv) && rv[j] <= a; j++ {
			b := rv[j]
			operands := uint64(a) | uint64(b)<<32
			c.check(a+b, tl[0], operands)
			if a != b {
				c.check(a-b, tl[1], operands)
			}
			if b != 1 {
				c.check(a*b, tl[2], operands)
				c.check(exact(quotient(a, ri[j]), b, a), tl[3], operands)
			}
		}
		// Pair with the remaining larger right values where a is the smaller
		ia := 1 / float64(a)
		for ; j < len(rv); j++ {
			b := rv[j]
			operands := uint64(b) | uint64(a)<<32
			c.check(b+a, tr[0], operands)
			c.check(b-a, tr[1], operands)
			if a != 1 {
				c.check(b*a, tr[2], operands)
				c.check(exact(quotient(b, ia), a, b), tr[3], operands)
			}
		}
	}
}

// lookup returns the index of value among the sorted entries of a built subset which always has at least one
func lookup(values []entry, value uint32) (int, bool) {
	// Halve the range without branching so unpredictable comparisons cost no mispredicted branch
	base, n := 0, len(values)
	for n > 1 {
		half := n / 2
		// Build an all-ones mask when the middle value is at most the one sought since Go would branch on the comparison
		base += half & int(^((int64(value) - int64(values[base+half].value())) >> 63))
		n -= half
	}
	return base, values[base].value() == value
}

// partner is a number that combines with another under an operator to make the target
type partner struct {
	value uint32
	op    byte
}

// partners fills buf with every number that combines with n under Countdown rules to make the target in operator order
func partners(n, target uint32, buf *[6]partner) []partner {
	count := 0
	if target > n {
		buf[count] = partner{target - n, '+'}
		count++
	}
	if n > target {
		buf[count] = partner{n - target, '-'}
		count++
	}
	buf[count] = partner{n + target, '-'}
	count++
	// Divide only when the quotient could be at least two since neither operand may be one
	if n != 1 && 2*n <= target && target%n == 0 {
		buf[count] = partner{target / n, '*'}
		count++
	}
	if n >= 2*target && n%target == 0 {
		buf[count] = partner{n / target, '/'}
		count++
	}
	// Skip a product too large for any subset to make
	if n != 1 && uint64(n)*uint64(target) <= math.MaxUint32 {
		buf[count] = partner{n * target, '/'}
		count++
	}
	return buf[:count]
}

// findExact returns how the target is first made from a subset without building all of its values
func (s *state) findExact(mask uint) (entry, bool) {
	var buf [6]partner
	for left := (mask - 1) & mask; left != 0; left = (left - 1) & mask {
		right := mask ^ left
		// Visit splits in the same order as building so the same origin wins
		if left >= right {
			continue
		}
		lefts, rights := s.vals[left], s.vals[right]
		// Skip searches for values outside each half's range
		leftLow, leftHigh := lefts[0].value(), lefts[len(lefts)-1].value()
		rightLow, rightHigh := rights[0].value(), rights[len(rights)-1].value()
		// Keep the lowest pair as building would since partners come in operator order
		bestA, bestB, bestOp := uint32(math.MaxUint32), uint32(math.MaxUint32), byte(0)
		if len(lefts) <= len(rights) {
			// Take the first left value with any partner on the right since left values ascend
			for _, e := range lefts {
				for _, p := range partners(e.value(), s.target, &buf) {
					if p.value < bestB && p.value >= rightLow && p.value <= rightHigh {
						if _, ok := lookup(rights, p.value); ok {
							bestA, bestB, bestOp = e.value(), p.value, p.op
						}
					}
				}
				if bestOp != 0 {
					break
				}
			}
		} else {
			for _, e := range rights {
				for _, p := range partners(e.value(), s.target, &buf) {
					if p.value < bestA && p.value >= leftLow && p.value <= leftHigh {
						if _, ok := lookup(lefts, p.value); ok {
							bestA, bestB, bestOp = p.value, e.value(), p.op
						}
					}
				}
			}
		}
		if bestOp != 0 {
			if bestA >= bestB {
				return entry{template(bestOp, left, right) | uint64(s.target), uint64(bestA) | uint64(bestB)<<32}, true
			}
			return entry{template(bestOp, right, left) | uint64(s.target), uint64(bestB) | uint64(bestA)<<32}, true
		}
	}
	return entry{}, false
}

// build sorts the reachable values of a subset into a worker's arena with a bitset of at least words words
func (s *state) build(w *scratch, mask uint, words int) {
	s.ready(w, words)
	seen := w.seen
	count := 0
	// Mark zero as seen so inexact divisions never become entries
	seen[0] |= 1
	for left := (mask - 1) & mask; left != 0; left = (left - 1) & mask {
		right := mask ^ left
		// Visit each split once rather than once per ordering
		if left >= right {
			continue
		}
		// Reserve room for every pair's results plus the one slot each store may write past the end
		pairs := 4 * len(s.vals[left]) * len(s.vals[right])
		w.tmp = grow(w.tmp, count, count+min(pairs, int(s.max[mask]))+1)
		count = s.emitSplit(w, left, right, count)
	}
	seen[0] &^= 1

	candidates := w.tmp[:count]
	top := len(w.arena)
	// Start a fresh block when full rather than copying since other subsets still point into the old one
	if top+count > cap(w.arena) {
		w.arena = make([]entry, 0, max(2*cap(w.arena), count, 4096))
		top = 0
	}
	w.arena = w.arena[:top+count]
	sorted := w.arena[top : top+count : top+count]
	if count < rankMin {
		// Clear only the words this subset touched and insertion sort the few values
		for i, e := range candidates {
			seen[e.value()>>6] = 0
			k := i
			for ; k > 0 && sorted[k-1].value() > e.value(); k-- {
				sorted[k] = sorted[k-1]
			}
			sorted[k] = e
		}
	} else {
		// Place each value at its rank in the bitset which needs no comparisons
		words := s.max[mask]/64 + 1
		seenWords, rank := seen[:words], w.rank[:words]
		below := uint32(0)
		for i, word := range seenWords {
			rank[i] = below
			below += uint32(bits.OnesCount64(word))
		}
		for _, e := range candidates {
			v := e.value()
			lower := seenWords[v>>6] & (1<<(v&63) - 1)
			sorted[rank[v>>6]+uint32(bits.OnesCount64(lower))] = e
		}
		clear(seenWords)
	}
	s.vals[mask] = sorted
}

func distance(value, target uint32) uint32 {
	if value > target {
		return value - target
	}
	return target - value
}

// render writes the expression for an entry following its origins back to the pool with brackets when asked
func (s *state) render(e entry, out *strings.Builder, bracket bool) {
	if e.op() == 0 {
		out.WriteString(strconv.FormatUint(uint64(e.value()), 10))
		return
	}
	at := func(mask uint8, value uint32) entry {
		values := s.vals[mask]
		i, _ := lookup(values, value)
		return values[i]
	}
	if bracket {
		out.WriteByte('(')
	}
	s.render(at(e.largerMask(), e.larger()), out, true)
	out.WriteByte(' ')
	out.WriteByte(e.op())
	out.WriteByte(' ')
	s.render(at(e.smallerMask(), e.smaller()), out, true)
	if bracket {
		out.WriteByte(')')
	}
}

// workOf estimates the values a size's searches scan and the pairs its builds combine
func (s *state) workOf(masks []uint8) (scan, pairs int) {
	for _, m := range masks {
		mask := uint(m)
		for left := (mask - 1) & mask; left != 0; left = (left - 1) & mask {
			if right := mask ^ left; left < right {
				l, r := len(s.vals[left]), len(s.vals[right])
				scan += min(l, r)
				pairs += l * r
			}
		}
	}
	return scan, pairs
}

// searchSize returns how the target is first made from the lowest subset among masks that can make it
func (s *state) searchSize(p *pool, masks []uint8) (entry, bool) {
	// Search in turn when the work is too small to repay waking the workers
	if p.workers == 1 || len(masks) == 1 {
		return s.searchEach(masks)
	}
	if scan, _ := s.workOf(masks); scan < searchMin {
		return s.searchEach(masks)
	}
	// Record each subset's answer by its position so the lowest mask wins whichever worker finds it first
	var hits [64]entry
	var lowest atomic.Int32
	lowest.Store(int32(len(masks)))
	p.run(len(masks), func(_, t int) {
		// Skip subsets after one already known to make the target
		if int32(t) > lowest.Load() {
			return
		}
		if e, ok := s.findExact(uint(masks[t])); ok {
			hits[t] = e
			for {
				low := lowest.Load()
				if int32(t) >= low || lowest.CompareAndSwap(low, int32(t)) {
					break
				}
			}
		}
	})
	if low := int(lowest.Load()); low < len(masks) {
		return hits[low], true
	}
	return entry{}, false
}

// searchEach returns how the target is first made from the lowest subset among masks searching them in turn
func (s *state) searchEach(masks []uint8) (entry, bool) {
	for _, m := range masks {
		if e, ok := s.findExact(uint(m)); ok {
			return e, true
		}
	}
	return entry{}, false
}

// buildSize stores the values of every subset among masks spreading the subsets over the workers when worthwhile
func (s *state) buildSize(p *pool, masks []uint8, words int) {
	if p.workers > 1 {
		if _, pairs := s.workOf(masks); pairs >= buildMin {
			// Size each worker's bitset by the subsets it builds so workers given small subsets stay in cache
			p.run(len(masks), func(worker, t int) {
				s.build(&s.work[worker], uint(masks[t]), int(s.max[masks[t]]/64+1))
			})
			return
		}
	}
	// Size the bitset once for the whole size as the sequential solver does
	for _, m := range masks {
		s.build(&s.work[0], uint(m), words)
	}
}

// closestWhole returns the whole pool's value closest to the target with the first way of making it
func (s *state) closestWhole(p *pool) checker {
	var splits [32]uint
	count, pairs := 0, 0
	for left := (s.full - 1) & s.full; left != 0; left = (left - 1) & s.full {
		if right := s.full ^ left; left < right {
			splits[count] = left
			count++
			pairs += len(s.vals[left]) * len(s.vals[right])
		}
	}
	start := checker{target: s.target, distance: math.MaxUint32, best: entry{math.MaxUint32, 0}}
	if p.workers == 1 || pairs < closestMin {
		c := start
		s.readyRights(&s.work[0])
		for _, left := range splits[:count] {
			s.checkSplit(&s.work[0], &c, left, s.full^left)
		}
		return c
	}
	// Check each split separately then fold them in split order so the earliest of equally good values wins
	var found [32]checker
	p.run(count, func(worker, t int) {
		w := &s.work[worker]
		s.readyRights(w)
		found[t] = start
		s.checkSplit(w, &found[t], splits[t], s.full^splits[t])
	})
	c := start
	for _, f := range found[:count] {
		if f.distance < c.distance || (f.distance == c.distance && f.best.value() < c.best.value()) {
			c = f
		}
	}
	return c
}

// solve returns the simplest expression that hits the target or gets closest to it with its value
func solve(target uint32, pool []uint32) (uint32, string) {
	p := workerPool()
	s := &state{target: target, full: 1<<len(pool) - 1, work: make([]scratch, p.workers)}

	// Work out each subset's largest value since subtracting and dividing never exceed the larger operand
	var largest [10]uint32
	for mask := uint(1); mask <= s.full; mask++ {
		if mask&(mask-1) == 0 {
			s.max[mask] = pool[bits.TrailingZeros(mask)]
		} else {
			for left := (mask - 1) & mask; left != 0; left = (left - 1) & mask {
				a, b := uint64(s.max[left]), uint64(s.max[mask^left])
				s.max[mask] = uint32(max(uint64(s.max[mask]), a*b, a+b))
			}
		}
		// Track the largest value of each size so the bitset only grows when bigger subsets are built
		size := bits.OnesCount(mask)
		largest[size] = max(largest[size], s.max[mask])
	}

	// Store each pool number as a one-number subset
	singles := make([]entry, len(pool))
	var best entry
	solved := false
	for i, n := range pool {
		singles[i] = entry{uint64(n), 0}
		s.vals[1<<i] = singles[i : i+1 : i+1]
		if !solved && n == target {
			best, solved = singles[i], true
		}
	}

	// List subsets by size then mask so the loops below need no unpredictable size test
	var order [256]uint8
	var first [10]int
	for mask := uint(1); mask <= s.full; mask++ {
		first[bits.OnesCount(mask)+1]++
	}
	for size := 1; size <= len(pool)+1; size++ {
		first[size] += first[size-1]
	}
	fill := first
	for mask := uint(1); mask <= s.full; mask++ {
		order[fill[bits.OnesCount(mask)]] = uint8(mask)
		fill[bits.OnesCount(mask)]++
	}

	// Work through subsets smallest first stopping at the first size that hits the target
	for size := 2; size <= len(pool) && !solved; size++ {
		masks := order[first[size]:first[size+1]]
		// Keep the lowest matching subset of this size to break ties the same way every run
		if best, solved = s.searchSize(p, masks); solved {
			break
		}
		// Skip building the whole pool's values since no larger subset is made from them
		if size == len(pool) {
			break
		}
		for _, m := range order[:first[size]] {
			s.rightsMax = max(s.rightsMax, len(s.vals[m]))
		}
		s.buildSize(p, masks, int(largest[size]/64+1))
	}

	if !solved {
		// Rank by distance from the target then by how many numbers are used so the simplest answer wins
		bestDistance, bestUsed := uint32(math.MaxUint32), 99
		for mask := uint(1); mask < s.full; mask++ {
			used := bits.OnesCount(mask)
			for _, e := range s.vals[mask] {
				d := distance(e.value(), target)
				if d < bestDistance || (d == bestDistance && used < bestUsed) {
					best, bestDistance, bestUsed = e, d, used
				}
			}
		}
		// Check the whole pool's values as they are made since no larger subset is built from them
		if len(pool) > 1 {
			for _, m := range order[:first[len(pool)]] {
				s.rightsMax = max(s.rightsMax, len(s.vals[m]))
			}
			c := s.closestWhole(p)
			// Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
			if c.distance < bestDistance {
				best = c.best
			}
		} else if bestDistance == math.MaxUint32 {
			// Answer with the only number when a one-number pool misses the target
			best = singles[0]
		}
	}

	// Render without outer brackets which matches stripping them from the bracketed form
	var out strings.Builder
	s.render(best, &out, false)
	return best.value(), out.String()
}
