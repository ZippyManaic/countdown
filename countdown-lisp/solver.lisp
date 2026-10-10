;;;; Work out the simplest Countdown expression that hits a target or gets closest to it

(defpackage :countdown-solver
  (:use :common-lisp)
  (:export #:solve))

(in-package :countdown-solver)

(declaim (optimize (speed 3) (safety 0) (debug 0)))

(deftype u32 () '(unsigned-byte 32))
(deftype u64 () '(unsigned-byte 64))
(deftype u32s () '(simple-array (unsigned-byte 32) (*)))
(deftype u64s () '(simple-array (unsigned-byte 64) (*)))
(deftype doubles () '(simple-array double-float (*)))
(deftype index () '(integer 0 #.(ash 1 40)))

;; Number the operators in the order they are tried so ties keep the lowest
(defconstant +add+ 0)
(defconstant +sub+ 1)
(defconstant +mul+ 2)
(defconstant +div+ 3)

;; Sort subsets with fewer values than this by insertion rather than by rank in the bitset
(defconstant +rank-min+ 16)

;; Radix sort a subset when its bitset has more than this many words per value
(defconstant +sparse+ 64)

;; Pack an origin as larger value shifted by eight then the larger operand's mask shifted by two then the operator
(declaim (inline origin))
(defun origin (larger larger-mask op)
  (declare (type u32 larger) (type (integer 0 63) larger-mask) (type (integer 0 3) op))
  (logior (ash larger 8) (ash larger-mask 2) op))

;; Hold the working memory of one solve with each subset's values and origins at an offset in the arena
(defstruct (state (:constructor make-state (target n)))
  (target 0 :type u32)
  (n 0 :type (integer 0 6))
  (vals (make-array 256 :element-type 'u32) :type u32s)
  (orgs (make-array 256 :element-type 'u64) :type u64s)
  (top 0 :type index)
  (off (make-array 64 :element-type 'u32 :initial-element 0) :type u32s)
  (len (make-array 64 :element-type 'u32 :initial-element 0) :type u32s)
  (max (make-array 64 :element-type 'u64 :initial-element 0) :type u64s)
  (seen (make-array 1 :element-type 'u64 :initial-element 0) :type u64s)
  (rank (make-array 1 :element-type 'u32 :initial-element 0) :type u32s)
  (tmp-vals (make-array 256 :element-type 'u32) :type u32s)
  (tmp-orgs (make-array 256 :element-type 'u64) :type u64s)
  (right-vals (make-array 64 :element-type 'u32) :type u32s)
  (right-inv (make-array 64 :element-type 'double-float) :type doubles))

(declaim (inline grow-u32 grow-u64))
(defun grow-u32 (old need keep)
  "Return old or a larger copy of its first keep elements when it holds fewer than need"
  (declare (type u32s old) (type index need keep))
  (if (>= (length old) need)
      old
      (let ((new (make-array (max need (* 2 (length old))) :element-type 'u32)))
        (replace new old :end2 keep)
        new)))

(defun grow-u64 (old need keep)
  "Return old or a larger copy of its first keep elements when it holds fewer than need"
  (declare (type u64s old) (type index need keep))
  (if (>= (length old) need)
      old
      (let ((new (make-array (max need (* 2 (length old))) :element-type 'u64)))
        (replace new old :end2 keep)
        new)))

(declaim (inline quotient))
(defun quotient (x inv)
  "Return x divided by a number whose reciprocal is inv rounded to the nearest integer"
  (declare (type u32 x) (type double-float inv))
  (values (truncate (+ (* (coerce x 'double-float) inv) 0.5d0))))

(declaim (inline lookup))
(defun lookup (vals base n value)
  "Return the arena index holding value among n sorted values from base or minus one when it is absent"
  (declare (type u32s vals) (type index base n) (type u32 value))
  (if (or (zerop n) (< value (aref vals base)) (> value (aref vals (+ base n -1))))
      -1
      (progn
        ;; Halve the range with a conditional move so unpredictable comparisons cost no mispredicted branch
        (loop while (> n 1)
              do (let ((half (ash n -1)))
                   (declare (type index half))
                   (setf base (+ base (if (<= (aref vals (+ base half)) value) half 0)))
                   (decf n half)))
        (if (= (aref vals base) value) base -1))))

(defmacro do-ops ((emit x y inv larger-mask) &body tail)
  "Expand to an emit of every legal value from x at least y with origins naming larger-mask as the larger side"
  `(let ((x ,x) (y ,y))
     (declare (type u32 x y))
     (,emit (+ x y) (origin x ,larger-mask +add+))
     ;; Skip a zero result since every intermediate value must be a positive integer
     (when (/= x y)
       (,emit (- x y) (origin x ,larger-mask +sub+)))
     ;; Skip multiplying and dividing by one as they never produce a new value
     (when (/= y 1)
       (,emit (* x y) (origin x ,larger-mask +mul+))
       ;; Emit zero for an inexact division since bit zero stays set so it is dropped
       (let ((q (quotient x ,inv)))
         (declare (type u32 q))
         (,emit (if (= (* q y) x) q 0) (origin x ,larger-mask +div+))))
     ,@tail))

(defmacro do-pairs ((s left right emit) &body tail)
  "Expand to an emit of every legal combination of each left value with each right value"
  `(let* ((vals (state-vals ,s))
          (lo (aref (state-off ,s) ,left)) (nl (aref (state-len ,s) ,left))
          (ro (aref (state-off ,s) ,right)) (nr (aref (state-len ,s) ,right))
          (rv (state-right-vals ,s)) (ri (state-right-inv ,s)))
     (declare (type u32s vals rv) (type doubles ri) (type index lo nl ro nr))
     ;; Invert each right value once per split rather than once per pair
     (dotimes (j nr)
       (let ((b (aref vals (+ ro j))))
         (setf (aref rv j) b (aref ri j) (/ 1d0 (coerce b 'double-float)))))
     (dotimes (i nl)
       (let ((a (aref vals (+ lo i))) (j 0))
         (declare (type u32 a) (type index j))
         ;; Pair with right values up to a first where a is the larger and ties go left
         (loop while (and (< j nr) (<= (aref rv j) a))
               do (do-ops (,emit a (aref rv j) (aref ri j) ,left))
                  (incf j))
         (let ((ia (/ 1d0 (coerce a 'double-float))))
           (loop while (< j nr)
                 do (do-ops (,emit (aref rv j) a ia ,right))
                    (incf j)))))
     ,@tail))

(defun reserve (s need-tmp)
  "Make room in the scratch lists for need-tmp entries and in the right-hand buffers for any subset"
  (declare (type state s) (type index need-tmp))
  (setf (state-tmp-vals s) (grow-u32 (state-tmp-vals s) need-tmp (length (state-tmp-vals s)))
        (state-tmp-orgs s) (grow-u64 (state-tmp-orgs s) need-tmp (length (state-tmp-orgs s)))))

(defun reserve-rights (s)
  "Make room for the values and reciprocals of the largest subset built so far"
  (declare (type state s))
  (let ((most 0))
    (declare (type index most))
    (loop for m from 1 below 64 do (setf most (max most (aref (state-len s) m))))
    (when (> most (min (length (state-right-vals s)) (length (state-right-inv s))))
      (setf (state-right-vals s) (make-array (* 2 most) :element-type 'u32)
            (state-right-inv s) (make-array (* 2 most) :element-type 'double-float)))))

(defun reserve-seen (s largest)
  "Make the bitset and its ranks cover every value up to largest"
  (declare (type state s) (type u64 largest))
  (let ((words (1+ (ash largest -6))))
    (when (> words (length (state-seen s)))
      ;; Replace rather than copy since building leaves the bitset clear
      (setf (state-seen s) (make-array words :element-type 'u64 :initial-element 0)
            (state-rank s) (make-array words :element-type 'u32 :initial-element 0)))))

(defun build (s mask)
  "Build the sorted reachable values of a subset into the arena keeping only the first way found to make each"
  (declare (type state s) (type (integer 1 63) mask))
  (let ((seen (state-seen s))
        (count 0)
        (bound (aref (state-max s) mask)))
    (declare (type u64s seen) (type index count))
    ;; Mark zero as seen so inexact divisions never become entries
    (setf (aref seen 0) (logior (aref seen 0) 1))
    (loop for left of-type (integer 0 63) = (logand (1- mask) mask) then (logand (1- left) mask)
          until (zerop left)
          do (let ((right (logxor mask left)))
               ;; Visit each split once rather than once per ordering
               (when (< left right)
                 ;; Reserve room for every pair's results plus the one slot each store may write past the end
                 (let ((pairs (* 4 (aref (state-len s) left) (aref (state-len s) right))))
                   (reserve s (+ count (min pairs bound) 1)))
                 (let ((tv (state-tmp-vals s)) (to (state-tmp-orgs s)))
                   (declare (type u32s tv) (type u64s to))
                   ;; Store every value and advance only past new ones so duplicates cost no mispredicted branch
                   (macrolet ((emit (v o)
                                `(let* ((v ,v) (w (aref seen (ash v -6))) (bit (logand v 63)))
                                   (declare (type u32 v) (type u64 w))
                                   (setf (aref seen (ash v -6)) (logior w (ash 1 bit))
                                         (aref tv count) v
                                         (aref to count) ,o)
                                   (incf count (- 1 (logand (ash w (- bit)) 1))))))
                     (do-pairs (s left right emit)))))))
    (setf (aref seen 0) (logand (aref seen 0) (lognot 1)))
    (let* ((top (state-top s))
           (vals (grow-u32 (state-vals s) (+ top count) top))
           (orgs (grow-u64 (state-orgs s) (+ top count) top))
           (tv (state-tmp-vals s))
           (to (state-tmp-orgs s)))
      (declare (type index top) (type u32s vals tv) (type u64s orgs to))
      (setf (state-vals s) vals (state-orgs s) orgs)
      (cond
        ((< count +rank-min+)
          ;; Clear only the words this subset touched and insertion sort the few values
          (dotimes (i count)
            (let ((v (aref tv i)) (o (aref to i)) (k i))
              (declare (type index k))
              (setf (aref seen (ash v -6)) 0)
              (loop while (and (> k 0) (> (aref vals (+ top k -1)) v))
                    do (setf (aref vals (+ top k)) (aref vals (+ top k -1))
                             (aref orgs (+ top k)) (aref orgs (+ top k -1)))
                       (decf k))
              (setf (aref vals (+ top k)) v (aref orgs (+ top k)) o))))
        ((> (1+ (ash bound -6)) (* +sparse+ count))
          ;; Radix sort sparse subsets so the cost follows the values found rather than the range they could span
          (let ((counts (make-array (* 3 2048) :element-type 'u32 :initial-element 0)))
            (declare (type u32s counts))
            (dotimes (i count)
              (let ((v (aref tv i)))
                (declare (type u32 v))
                (setf (aref seen (ash v -6)) 0)
                (incf (aref counts (logand v 2047)))
                (incf (aref counts (+ 2048 (logand (ash v -11) 2047))))
                (incf (aref counts (+ 4096 (ash v -22))))))
            ;; Pass from tmp to the arena and back so the third pass lands in the arena
            (flet ((pass (p from-vals from-orgs from-at to-vals to-orgs to-at)
                     (declare (type (integer 0 2) p) (type u32s from-vals to-vals) (type u64s from-orgs to-orgs) (type index from-at to-at))
                     (let ((c (* 2048 p)) (shift (* -11 p)) (sum 0))
                       (declare (type index c sum))
                       (loop for d of-type index from c below (+ c 2048)
                             do (let ((n (aref counts d)))
                                  (setf (aref counts d) sum)
                                  (incf sum n)))
                       (dotimes (i count)
                         (let* ((v (aref from-vals (+ from-at i)))
                                (d (+ c (logand (ash v shift) 2047)))
                                (at (+ to-at (aref counts d))))
                           (declare (type u32 v) (type index d at))
                           (setf (aref counts d) (1+ (aref counts d))
                                 (aref to-vals at) v
                                 (aref to-orgs at) (aref from-orgs (+ from-at i))))))))
              (declare (inline pass))
              (pass 0 tv to 0 vals orgs top)
              (pass 1 vals orgs top tv to 0)
              (pass 2 tv to 0 vals orgs top))))
        (t
          ;; Place each value at its rank in the bitset which needs no comparisons
          (let ((words (1+ (ash bound -6))) (below 0) (rank (state-rank s)))
            (declare (type index words below) (type u32s rank))
            (dotimes (w words)
              (setf (aref rank w) below)
              (incf below (logcount (aref seen w))))
            (dotimes (i count)
              (let* ((v (aref tv i))
                     (lower (ldb (byte (logand v 63) 0) (aref seen (ash v -6))))
                     (at (+ top (aref rank (ash v -6)) (logcount lower))))
                (declare (type u32 v) (type u64 lower) (type index at))
                (setf (aref vals at) v (aref orgs at) (aref to i))))
            (fill seen 0 :end words))))
      (setf (aref (state-off s) mask) top
            (aref (state-len s) mask) count
            (state-top s) (+ top count)))))

(defmacro with-partners ((m op n target) &body body)
  "Run body with m and op bound to every number that combines with n to make the target in operator order"
  `(flet ((try (,m ,op)
            (declare (type u64 ,m) (type (integer 0 3) ,op))
            ,@body))
     (declare (inline try))
     (let ((n ,n) (target ,target))
       (declare (type u32 n target))
       (when (> target n) (try (- target n) +add+))
       (when (> n target) (try (- n target) +sub+))
       (try (+ n target) +sub+)
       ;; Divide only when the quotient could be at least two since neither operand may be one
       (when (and (/= n 1) (<= (* 2 n) target) (zerop (mod target n)))
         (try (floor target n) +mul+))
       (when (and (>= n (* 2 target)) (zerop (mod n target)))
         (try (floor n target) +div+))
       (when (/= n 1)
         (try (* n target) +div+)))))

(defun find-exact (s mask)
  "Return the origin of the first way the target is made from a subset or minus one without building its values"
  (declare (type state s) (type (integer 1 63) mask))
  (let ((vals (state-vals s)) (target (state-target s)))
    (declare (type u32s vals))
    (loop for left of-type (integer 0 63) = (logand (1- mask) mask) then (logand (1- left) mask)
          until (zerop left)
          do (let ((right (logxor mask left)))
               ;; Visit splits in the same order as building so the same origin wins
               (when (< left right)
                 (let ((lo (aref (state-off s) left)) (nl (aref (state-len s) left))
                       (ro (aref (state-off s) right)) (nr (aref (state-len s) right))
                       (best-a #xFFFFFFFF) (best-b #xFFFFFFFF) (best-op -1))
                   (declare (type index lo nl ro nr) (type u64 best-a best-b) (type fixnum best-op))
                   (if (<= nl nr)
                       ;; Take the first left value with any partner on the right since left values ascend
                       (loop for i from 0 below nl
                             while (< best-op 0)
                             do (let ((a (aref vals (+ lo i))))
                                  (with-partners (m op a target)
                                    (when (and (< m best-b) (>= (lookup vals ro nr m) 0))
                                      (setf best-a a best-b m best-op op)))))
                       (dotimes (j nr)
                         (let ((b (aref vals (+ ro j))))
                           (with-partners (m op b target)
                             (when (and (< m best-a) (>= (lookup vals lo nl m) 0))
                               (setf best-a m best-b b best-op op))))))
                   (when (>= best-op 0)
                     (return-from find-exact
                       (if (>= best-a best-b)
                           (origin best-a left best-op)
                           (origin best-b right best-op))))))))
    -1))

(defun write-expr (s mask value org out bracket)
  "Write the expression for a value of a subset following origins back to the pool"
  (declare (type state s) (type (integer 0 63) mask) (type u32 value) (type u64 org))
  (if (zerop org)
      (let ((*print-base* 10)) (princ value out))
      (let* ((op (logand org 3))
             (larger-mask (logand (ash org -2) 63))
             (larger (ash org -8))
             (smaller-mask (logxor mask larger-mask))
             (smaller (case op
                        (#.+add+ (- value larger))
                        (#.+sub+ (- larger value))
                        (#.+mul+ (floor value larger))
                        (t (floor larger value))))
             (vals (state-vals s))
             (orgs (state-orgs s)))
        (declare (type u32 larger smaller))
        (when bracket (write-char #\( out))
        (write-expr s larger-mask larger
                    (aref orgs (lookup vals (aref (state-off s) larger-mask) (aref (state-len s) larger-mask) larger))
                    out t)
        (write-char #\Space out)
        (write-char (schar "+-*/" op) out)
        (write-char #\Space out)
        (write-expr s smaller-mask smaller
                    (aref orgs (lookup vals (aref (state-off s) smaller-mask) (aref (state-len s) smaller-mask) smaller))
                    out t)
        (when bracket (write-char #\) out)))))

(defun solve (target pool)
  "Return the value and text of the simplest expression that hits the target or gets closest to it"
  (let* ((n (length pool))
         (full (1- (ash 1 n)))
         (s (make-state target n))
         (pool (coerce pool 'simple-vector))
         (largest (make-array 8 :element-type 'u64 :initial-element 0))
         (best-mask 0) (best-value target) (best-org 0) (found nil))
    (declare (type (integer 1 6) n) (type (integer 1 63) full) (type u32 target best-value)
             (type (integer 0 63) best-mask) (type u64 best-org))
    ;; Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    (let ((mx (state-max s)))
      (loop for mask from 1 to full
            do (if (zerop (logand mask (1- mask)))
                   (setf (aref mx mask) (svref pool (1- (integer-length mask))))
                   (loop for left of-type (integer 0 63) = (logand (1- mask) mask) then (logand (1- left) mask)
                         until (zerop left)
                         do (let* ((a (aref mx left)) (b (aref mx (logxor mask left)))
                                   (m (max (* a b) (+ a b))))
                              (declare (type (unsigned-byte 32) a b))
                              (setf (aref mx mask) (max m (aref mx mask))))))
               ;; Track the largest value of each size so the bitset only grows when bigger subsets are built
               (let ((size (logcount mask)))
                 (setf (aref largest size) (max (aref largest size) (aref mx mask))))))
    ;; Store each pool number as a one-number subset
    (dotimes (i n)
      (let ((v (svref pool i)))
        (setf (aref (state-vals s) i) v
              (aref (state-orgs s) i) 0
              (aref (state-off s) (ash 1 i)) i
              (aref (state-len s) (ash 1 i)) 1)
        (when (and (not found) (= v target))
          (setf found t best-mask (ash 1 i) best-org 0))))
    (setf (state-top s) n)
    ;; Work through subsets smallest first stopping at the first size that hits the target
    (loop for size from 2 to n
          until found
          do (loop for mask from 1 to full
                   until found
                   when (= (logcount mask) size)
                     ;; Keep the lowest matching subset of this size to break ties the same way every run
                     do (let ((org (find-exact s mask)))
                          (when (>= org 0)
                            (setf found t best-mask mask best-org org))))
             ;; Skip building the whole pool's values since no larger subset is made from them
             (when (or found (= size n)) (loop-finish))
             (reserve-rights s)
             (reserve-seen s (aref largest size))
             (loop for mask from 1 to full
                   when (= (logcount mask) size)
                     do (build s mask)))
    (unless found
      ;; Rank by distance from the target then by how many numbers are used so the simplest answer wins
      (let ((best-distance #xFFFFFFFF) (best-used 99) (vals (state-vals s)) (orgs (state-orgs s)))
        (declare (type u64 best-distance) (type fixnum best-used))
        ;; Include the only subset of a one-number pool since it is also the whole pool
        (loop for mask from 1 below (if (= n 1) 2 full)
              do (let ((used (logcount mask)) (off (aref (state-off s) mask)))
                   (dotimes (i (aref (state-len s) mask))
                     (let* ((v (aref vals (+ off i))) (d (abs (- v target))))
                       (when (or (< d best-distance) (and (= d best-distance) (< used best-used)))
                         (setf best-mask mask best-value v best-org (aref orgs (+ off i))
                               best-distance d best-used used))))))
        ;; Check the whole pool's values as they are made since no larger subset is built from them
        (when (> n 1)
          (reserve-rights s)
          (let ((whole-distance #xFFFFFFFF) (whole-value #xFFFFFFFF) (whole-org 0))
            (declare (type u64 whole-distance whole-value whole-org))
            ;; Keep a value as the whole pool's best if it is closer to the target or equally close and lower
            (macrolet ((check (v o)
                         `(let* ((v ,v) (d (abs (- v target))))
                            (declare (type u32 v))
                            (when (and (/= v 0)
                                       (or (< d whole-distance) (and (= d whole-distance) (< v whole-value))))
                              (setf whole-distance d whole-value v whole-org ,o)))))
              (loop for left of-type (integer 0 63) = (logand (1- full) full) then (logand (1- left) full)
                    until (zerop left)
                    do (let ((right (logxor full left)))
                         (when (< left right)
                           (do-pairs (s left right check))))))
            ;; Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
            (when (< whole-distance best-distance)
              (setf best-mask full best-value whole-value best-org whole-org))))))
    (values best-value
            (with-output-to-string (out)
              ;; Render without outer brackets which matches stripping them from the bracketed form
              (write-expr s best-mask best-value best-org out nil)))))
