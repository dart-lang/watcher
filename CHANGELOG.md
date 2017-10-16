# 0.9.8+1

* Change the type on a local function (_onBatch) to reflect the fact that its
  caller does not statically guarantee its contract.

# 0.9.8

* Improve support for symlinks. Where possible, symlinks are now treated as
  normal files. For caveats, see the README.

# 0.9.7+2

* Narrow the constraint on `async` to reflect the APIs this package is actually
  using.

# 0.9.7+1

* Fix all strong-mode warnings.

# 0.9.7

* Fix a bug in `FileWatcher` where events could be added after watchers were
  closed.

# 0.9.6

* Add a `Watcher` interface that encompasses watching both files and
  directories.

* Add `FileWatcher` and `PollingFileWatcher` classes for watching changes to
  individual files.

* Deprecate `DirectoryWatcher.directory`. Use `DirectoryWatcher.path` instead.

# 0.9.5

* Fix bugs where events could be added after watchers were closed.

# 0.9.4

* Treat add events for known files as modifications instead of discarding them
  on Mac OS.

# 0.9.3

* Improved support for Windows via `WindowsDirectoryWatcher`.

* Simplified `PollingDirectoryWatcher`.

* Fixed bugs in `MacOSDirectoryWatcher`
