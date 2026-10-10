;;;; Check the dealer in every mode and the solver against rounds with known answers

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

(multiple-value-bind (value expr) (countdown-solver:solve 999 '(10 10 25 50 75 100))
  (expect (and (= value 999) (string= expr "(((75 + 25) * 100) - 10) / 10")) "solves a four-large cats round"))
(multiple-value-bind (value expr) (countdown-solver:solve 100 '(1 1 2 2 3 3))
  (expect (and (= value 81) (string= expr "(((2 + 1) * (2 + 1)) * 3) * 3")) "reports closest on a no-large cats round"))
(multiple-value-bind (value expr) (countdown-solver:solve 999 '(2 3 87 62 37 12))
  (expect (and (= value 999) (string= expr "37 * ((87 / 3) - 2)")) "solves a nasty-cats round"))

(defun check-round (mode counts target pool)
  "Return the large count of a dealt round after checking it keeps the rules of its mode"
  (let ((large (remove-if-not (lambda (n) (> n 10)) pool)))
    (expect (and (<= 100 target 999) (= (length pool) 6)) "deals a target and six numbers")
    (expect (member (length large) counts) "deals an allowed large count")
    (expect (subsetp large (countdown:large-numbers mode)) "deals the mode's own large cards")
    (expect (= (length (remove-duplicates large)) (length large)) "deals distinct large cards")
    ;; Allow each small number at most twice since the deck holds two of each
    (expect (loop for s from 1 to 10 always (<= (count s pool) 2)) "deals each small number at most twice")
    (length large)))

(setf *random-state* (sb-ext:seed-random-state 1))
(dolist (mode '(:standard :cats :nasty))
  (let* ((counts (countdown:allowed-counts mode))
         (seen (loop repeat 2000
                     collect (multiple-value-bind (target pool) (countdown:generate-round mode)
                               (check-round mode counts target pool)))))
    (expect (equal (sort (remove-duplicates seen) #'<) counts) "deals every allowed large count")))
(dolist (mode '(:cats :nasty))
  (dotimes (k 5)
    (multiple-value-bind (target pool) (countdown:generate-round mode k)
      (expect (= (check-round mode (list k) target pool) k) "deals a fixed large count"))))

(expect (equal (countdown:parse-args '()) '(:standard nil)) "parses no arguments")
(expect (equal (countdown:parse-args '("nasty" "4")) '(:nasty 4)) "parses nasty 4")
(expect (equal (countdown:parse-args '("cats" "0")) '(:cats 0)) "parses cats 0")
(dolist (bad '(("standard" "3") ("cats" "5") ("dogs") ("cats" "1" "2") ("cats" "x")))
  (expect (null (countdown:parse-args bad)) (format nil "rejects ~{~A~^ ~}" bad)))

(if (zerop *failures*)
    (format t "all tests passed~%")
    (sb-ext:exit :code 1))
