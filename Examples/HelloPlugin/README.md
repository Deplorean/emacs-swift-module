# HelloPlugin

This example declares commands using Swift values and `async throws` closures.
`ModuleFactoryPlugin` generates the Emacs entry point from `createPlugin()`.

Build with Swift 6.4 on macOS 27:

```sh
swift build --package-path Examples/HelloPlugin
swift build --package-path Examples/HelloPlugin --show-bin-path
```

Load `libHelloPlugin.dylib` from the printed directory in an Emacs build that
supports dynamic modules:

```emacs-lisp
(module-load "/absolute/path/from/show-bin-path/libHelloPlugin.dylib")

(swift-hello "Emacs")                 ; => "Hello, Emacs!"
(swift-add 20 22)                     ; => 42
(swift-hello "")                      ; Signals a Swift error.

(setq hello-task
      (swift-hello-later
       "Emacs"
       (lambda (greeting) (message "%s" greeting))
       (lambda (failure) (message "Greeting failed: %s" failure))))

;; Cancel an outstanding operation.
(hello-plugin-cancel-task hello-task)

;; Release the plugin's async resources when it is no longer needed.
(hello-plugin-shutdown)
```

The asynchronous function returns a task identifier. Its callbacks run when
Emacs processes events. The success callback receives a string; the failure
callback receives a diagnostic string, including cancellation. Shutdown cancels
outstanding work and prevents further callback delivery.

Run the integration suites from any working directory:

```sh
Examples/HelloPlugin/run-native-tests.sh debug
Examples/HelloPlugin/run-native-tests.sh release
```

Set `SWIFT` or `EMACS` to an executable path to select a toolchain or Emacs build.
The tests use Emacs's bundled ERT library and require no Cask packages.

This example is part of EmacsSwiftModule and is licensed under
[GPL-3.0-or-later](../../LICENSE).
