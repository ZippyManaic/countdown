;;;; Time the solver over a file of rounds and write each answer as value tab expression

(defpackage :countdown-harness
  (:use :common-lisp)
  (:export #:main))

(in-package :countdown-harness)

(defun read-rounds (path)
  "Return each line of the file as a list of its numbers"
  (with-open-file (in path)
    (loop for line = (read-line in nil)
          while line
          collect (with-input-from-string (s line)
                    (loop for n = (read s nil) while n collect n)))))

(defun main ()
  "Solve every round reps times reporting the time per round and write the answers"
  (destructuring-bind (rounds-path out-path &optional (reps "1")) (rest sb-ext:*posix-argv*)
    (let* ((rounds (coerce (read-rounds rounds-path) 'vector))
           (reps (parse-integer reps))
           (values-out (make-array (length rounds)))
           (exprs (make-array (length rounds)))
           (start (get-internal-real-time)))
      (dotimes (k reps)
        (loop for r across rounds
              for i from 0
              do (multiple-value-bind (v e) (countdown-solver:solve (first r) (rest r))
                   (setf (aref values-out i) v (aref exprs i) e))))
      (let ((seconds (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
        (format *error-output* "~,4F ms/round~%" (/ (* seconds 1000.0d0) (* (length rounds) reps))))
      (with-open-file (out out-path :direction :output :if-exists :supersede)
        (dotimes (i (length rounds))
          (format out (if (zerop i) "~D~C~A" "~%~D~C~A") (aref values-out i) #\Tab (aref exprs i)))))))
