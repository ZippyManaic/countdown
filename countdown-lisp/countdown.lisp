;;;; Generate a Countdown numbers round and work out whether it can be solved

(defpackage :countdown
  (:use :common-lisp)
  (:export #:main))

(in-package :countdown)

(defparameter *large-numbers* '(25 50 75 100))

(defun shuffle (items)
  "Shuffle a vector in place with Fisher-Yates and return it"
  (loop for i from (1- (length items)) downto 1
        do (rotatef (aref items i) (aref items (random (1+ i)))))
  items)

(defun generate-round ()
  "Return a random target and a pool of six numbers with either one or two large numbers"
  (let* ((target (+ 100 (random 900)))
         (large-count (1+ (random 2)))
         ;; Hold two cards of each small number to match the game's deck
         (small (shuffle (coerce (loop for i from 0 below 20 collect (1+ (mod i 10))) 'vector)))
         ;; Shuffle a copy since each large number appears only once in the game
         (large (shuffle (coerce *large-numbers* 'vector))))
    (values target
            (append (coerce (subseq small 0 (- 6 large-count)) 'list)
                    (coerce (subseq large 0 large-count) 'list)))))

(defun main ()
  "Deal a round, print it and its answer and exit with zero only when the target is hit"
  ;; Seed from the system since a saved image would otherwise deal the same round every run
  (setf *random-state* (make-random-state t))
  (multiple-value-bind (target pool) (generate-round)
    (format t "Target: ~D~%" target)
    (format t "Pool:   ~{~D~^ ~}~%" pool)
    (multiple-value-bind (value expr) (countdown-solver:solve target pool)
      (if (= value target)
          (progn
            (format t "Solved: ~A = ~D~%" expr value)
            (sb-ext:exit :code 0))
          (progn
            (format t "No exact solution, closest is ~A = ~D (~D away)~%" expr value (abs (- target value)))
            (sb-ext:exit :code 1))))))
