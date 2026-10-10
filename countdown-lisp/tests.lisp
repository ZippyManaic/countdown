;;;; Check the solver against rounds with known answers

(defpackage :countdown-tests
  (:use :common-lisp))

(in-package :countdown-tests)

(defvar *failures* 0)

(defun expect (ok what)
  "Report a failed check by name and count it"
  (unless ok
    (format t "FAIL: ~A~%" what)
    (incf *failures*)))

(multiple-value-bind (value expr) (countdown-solver:solve 125 '(1 5 7 3 75 50))
  (expect (and (= value 125) (string= expr "75 + 50")) "finds simplest solution"))
(expect (= (countdown-solver:solve 552 '(8 4 2 5 100 25)) 552) "solves 552")
(expect (= (abs (- (countdown-solver:solve 974 '(8 8 6 8 25 100)) 974)) 1) "reports closest when unsolvable")
(multiple-value-bind (value expr) (countdown-solver:solve 431 '(3 2 3 4 2 25))
  (expect (and (= value 432) (string= expr "((25 * 3) - 3) * (4 + 2)")) "matches reference closest answer"))
(multiple-value-bind (value expr) (countdown-solver:solve 7 '(7))
  (expect (and (= value 7) (string= expr "7")) "handles a single number"))
(multiple-value-bind (value expr) (countdown-solver:solve 9 '(7))
  (expect (and (= value 7) (string= expr "7")) "reports a single number when it misses"))
(multiple-value-bind (value expr) (countdown-solver:solve 9 '(2 3))
  (expect (and (= value 6) (string= expr "3 * 2")) "handles smaller pools"))

(if (zerop *failures*)
    (format t "all tests passed~%")
    (sb-ext:exit :code 1))
