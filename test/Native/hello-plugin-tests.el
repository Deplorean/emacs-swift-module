;;; hello-plugin-tests.el --- Swift command integration tests -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)

(module-load
 (or (getenv "HELLO_PLUGIN_MODULE")
     (error "Set HELLO_PLUGIN_MODULE to libHelloPlugin.dylib")))

(defun hello-plugin-test--await (predicate)
  "Process Emacs events until PREDICATE succeeds, with a five-second deadline."
  (let ((deadline (+ (float-time) 5.0)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.01))
    (should (funcall predicate))))

(ert-deftest hello-plugin:registers-commands ()
  (dolist (command '(swift-hello swift-add swift-hello-later
                    hello-plugin-cancel-task hello-plugin-shutdown))
    (should (fboundp command)))
  (should (string-match-p "Greet NAME" (documentation #'swift-hello))))

(ert-deftest hello-plugin:string-unicode-and-embedded-nul ()
  (dolist (name (list "Emacs"
                     "Ελλάδα 日本語 🦀"
                     "e\u0301"
                     (concat "before" (string 0) "after")
                     (string 0)))
    (should (equal (swift-hello name) (concat "Hello, " name "!")))))

(ert-deftest hello-plugin:integer-conversion ()
  (should (= (swift-add 20 22) 42))
  (should (= (swift-add -12 5) -7))
  (should (= (swift-add 0 0) 0))
  (should (= (swift-add 9223372036854775807 0) 9223372036854775807))
  (should (= (swift-add -9223372036854775808 0) -9223372036854775808)))

(ert-deftest hello-plugin:wrong-arity ()
  (should-error (swift-hello) :type 'wrong-number-of-arguments)
  (should-error (swift-hello "one" "two") :type 'wrong-number-of-arguments)
  (should-error (swift-add 1) :type 'wrong-number-of-arguments)
  (should-error (swift-add 1 2 3) :type 'wrong-number-of-arguments)
  (should-error (swift-hello-later "name" #'ignore)
                :type 'wrong-number-of-arguments)
  (should-error (swift-hello-later "name" #'ignore #'ignore #'ignore)
                :type 'wrong-number-of-arguments))

(ert-deftest hello-plugin:wrong-types ()
  (dolist (value '(nil t 42 4.2 hello ("name") ["name"]))
    (should-error (swift-hello value) :type 'wrong-type-argument))
  (dolist (value '(nil t "42" 4.2 (42) [42]))
    (should-error (swift-add value 0) :type 'wrong-type-argument)
    (should-error (swift-add 0 value) :type 'wrong-type-argument))
  (should-error (swift-hello-later 42 #'ignore #'ignore)
                :type 'wrong-type-argument))

(ert-deftest hello-plugin:integer-input-out-of-range ()
  (should-error (swift-add 9223372036854775808 0))
  (should-error (swift-add -9223372036854775809 0))
  ;; A failed conversion must not leave a pending non-local exit.
  (should (= (swift-add 1 2) 3)))

(ert-deftest hello-plugin:swift-errors-and-recovery ()
  (let ((failure (should-error (swift-hello ""))))
    (should (string-match-p "A name must not be empty"
                            (error-message-string failure))))
  (let ((failure (should-error (swift-add 9223372036854775807 1))))
    (should (string-match-p "does not fit" (error-message-string failure))))
  (should-error (swift-add -9223372036854775808 -1))
  (should (equal (swift-hello "after an error") "Hello, after an error!")))

(ert-deftest hello-plugin:async-success-keeps-callbacks-alive ()
  (let ((successes nil)
        (failures nil)
        (name (concat "日本語" (string 0) "🦀")))
    (let ((task (swift-hello-later
                 name
                 (lambda (value) (push value successes))
                 (lambda (failure) (push failure failures)))))
      (should (integerp task))
      (garbage-collect)
      (hello-plugin-test--await (lambda () (or successes failures)))
      (should (equal successes (list (concat "Hello, " name "!"))))
      (should-not failures)
      (should-not (hello-plugin-cancel-task task)))))

(ert-deftest hello-plugin:async-swift-error ()
  (let ((successes nil)
        (failures nil))
    (swift-hello-later ""
                       (lambda (value) (push value successes))
                       (lambda (failure) (push failure failures)))
    (hello-plugin-test--await (lambda () (or successes failures)))
    (should-not successes)
    (should (= (length failures) 1))
    (should (stringp (car failures)))
    (should (string-match-p "A name must not be empty" (car failures)))))

(ert-deftest hello-plugin:async-cancellation ()
  (let ((successes nil)
        (failures nil))
    (let ((task (swift-hello-later
                 "cancelled"
                 (lambda (value) (push value successes))
                 (lambda (failure) (push failure failures)))))
      (should (hello-plugin-cancel-task task))
      (hello-plugin-test--await (lambda () (or successes failures)))
      (should-not successes)
      (should (= (length failures) 1))
      (should (stringp (car failures)))
      (should (> (length (car failures)) 0))
      (should-not (hello-plugin-cancel-task task)))))

(ert-deftest hello-plugin:async-many-tasks ()
  (let ((received (make-vector 24 nil))
        (failures nil)
        (completed 0)
        (tasks nil))
    (dotimes (index (length received))
      (let ((slot index))
        (push
         (swift-hello-later
          (format "task %d" slot)
          (lambda (value)
            (aset received slot value)
            (setq completed (1+ completed)))
          (lambda (failure) (push failure failures)))
         tasks)))
    (should (= (length (delete-dups (copy-sequence tasks))) (length tasks)))
    (garbage-collect)
    (hello-plugin-test--await
     (lambda () (or failures (= completed (length received)))))
    (should-not failures)
    (dotimes (index (length received))
      (should (equal (aref received index) (format "Hello, task %d!" index))))))

(ert-deftest hello-plugin:async-callback-can-start-another-command ()
  (let ((result nil)
        (failures nil))
    (swift-hello-later
     "outer"
     (lambda (outer)
       (swift-hello-later
        (swift-hello outer)
        (lambda (inner) (setq result inner))
        (lambda (failure) (push failure failures))))
     (lambda (failure) (push failure failures)))
    (hello-plugin-test--await (lambda () (or result failures)))
    (should-not failures)
    (should (equal result "Hello, Hello, Hello, outer!!!"))))

(ert-deftest hello-plugin:cancel-unknown-task ()
  (should-not (hello-plugin-cancel-task -1))
  (should-error (hello-plugin-cancel-task "task") :type 'wrong-type-argument)
  (should-error (hello-plugin-cancel-task) :type 'wrong-number-of-arguments))

;;; hello-plugin-tests.el ends here
