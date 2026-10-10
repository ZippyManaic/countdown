;;;; Generate a Countdown numbers round and work out whether it can be solved

(defpackage :countdown
  (:use :common-lisp)
  (:export #:main #:generate-round #:parse-args #:large-numbers #:allowed-counts))

(in-package :countdown)

(defparameter *usage* "usage: countdown [standard|cats|nasty] [LARGE]")

(defun large-numbers (mode)
  "Return the large cards of a mode, with nasty-cats using the cards of the 2010 specials"
  (if (eq mode :nasty) '(12 37 62 87) '(25 50 75 100)))

(defun allowed-counts (mode)
  "Return the large counts a mode allows"
  (if (eq mode :standard) '(1 2) '(0 1 2 3 4)))

(defun shuffle (items)
  "Shuffle a vector in place with Fisher-Yates and return it"
  (loop for i from (1- (length items)) downto 1
        do (rotatef (aref items i) (aref items (random (1+ i)))))
  items)

(defun generate-round (&optional (mode :standard) large-count)
  "Return a random target and six numbers with one or two large in standard mode and none to four otherwise"
  (let* ((target (+ 100 (random 900)))
         (large-count (or large-count (if (eq mode :standard) (1+ (random 2)) (random 5))))
         ;; Hold two cards of each small number to match the game's deck
         (small (shuffle (coerce (loop for i from 0 below 20 collect (1+ (mod i 10))) 'vector)))
         ;; Shuffle a copy since each large number appears only once in the game
         (large (shuffle (coerce (large-numbers mode) 'vector))))
    (values target
            (append (coerce (subseq small 0 (- 6 large-count)) 'list)
                    (coerce (subseq large 0 large-count) 'list)))))

(defun parse-args (args)
  "Return a list of the mode and fixed large count from the command line, or nil when the arguments are invalid"
  (let ((mode (if args
                  (cdr (assoc (first args) '(("standard" . :standard) ("cats" . :cats) ("nasty" . :nasty))
                              :test #'string=))
                  :standard)))
    (cond ((or (null mode) (> (length args) 2)) nil)
          ((< (length args) 2) (list mode nil))
          (t (let ((count (find (second args) (allowed-counts mode) :key #'princ-to-string :test #'string=)))
               (and count (list mode count)))))))

(defun main ()
  "Deal a round, print it and its answer and exit with zero only when the target is hit"
  ;; Seed from the system since a saved image would otherwise deal the same round every run
  (setf *random-state* (make-random-state t))
  (let ((parsed (parse-args (rest sb-ext:*posix-argv*))))
    (unless parsed
      (format *error-output* "~A~%" *usage*)
      (sb-ext:exit :code 2))
    (multiple-value-bind (target pool) (apply #'generate-round parsed)
      (format t "Target: ~D~%" target)
      (format t "Pool:   ~{~D~^ ~}~%" pool)
      (multiple-value-bind (value expr) (countdown-solver:solve target pool)
        (if (= value target)
            (progn
              (format t "Solved: ~A = ~D~%" expr value)
              (sb-ext:exit :code 0))
            (progn
              (format t "No exact solution, closest is ~A = ~D (~D away)~%" expr value (abs (- target value)))
              (sb-ext:exit :code 1)))))))
