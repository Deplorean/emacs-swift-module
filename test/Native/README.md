# Native plugin integration tests

Run `Examples/HelloPlugin/run-native-tests.sh debug` or pass `release`.
The script builds the example with the generated module entry point, then loads
the resulting dynamic library in real batch Emacs.

`hello-plugin-tests.el` checks command registration, documentation, Unicode,
embedded NUL characters, signed 64-bit integer limits, arity, type errors, thrown
Swift errors, recovery after errors, async results and failures, callback
retention across garbage collection, concurrent tasks, reentrant callbacks, and
cancellation.

`hello-plugin-shutdown-tests.el` runs in a fresh Emacs process. It checks that
shutdown is idempotent, discards pending callbacks, and rejects new async work.
Isolating shutdown keeps ERT's test order from affecting other cases.

Async tests process Emacs events with a five-second deadline instead of relying
on an external ERT async package. Failures propagate through ERT's batch exit
status. These tests require macOS 27, Swift 6.4, and Emacs with dynamic module
support.
