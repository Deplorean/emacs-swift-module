;;; hello-plugin-shutdown-tests.el --- Plugin shutdown tests -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)

(module-load
 (or (getenv "HELLO_PLUGIN_MODULE")
     (error "Set HELLO_PLUGIN_MODULE to libHelloPlugin.dylib")))

(ert-deftest hello-plugin:shutdown-cancels-pending-callbacks ()
  (let ((successes nil)
        (failures nil)
        (tasks nil))
    (dotimes (_ 8)
      (push
       (swift-hello-later
        "shutdown"
        (lambda (value) (push value successes))
        (lambda (failure) (push failure failures)))
       tasks))
    (should-not (hello-plugin-shutdown))
    (should-not (hello-plugin-shutdown))
    (garbage-collect)
    ;; Give the 100 ms operations time to finish while pumping process filters.
    (let ((deadline (+ (float-time) 0.5)))
      (while (< (float-time) deadline)
        (accept-process-output nil 0.01)))
    (should-not successes)
    (should-not failures)
    (dolist (task tasks)
      (should-not (hello-plugin-cancel-task task)))
    (should-error (swift-hello-later "after shutdown" #'ignore #'ignore))))

;;; hello-plugin-shutdown-tests.el ends here
