A file system watcher.

It monitors changes to contents of directories and sends notifications when
files have been added, removed, or modified.

## Symlinks

As best it can, this package treats valid symlinks as copies of the linked files
or directories, and broken symlinks as non-existent. However, there are some
caveats. In particular, due to limitations in the native file watching APIs for
various platforms, a watcher's behavior is undefined if:

* A target is added for a symlink that was previously broken.

* A symlink links to another symlink, and the second symlink is removed.

* A symlink links to a file or directory contained within another symlink, and
  the second symlink is removed.

* A symlink's own target changes. This is undefined only when using the polling
  watcher, due to [issue 24821][24821].

[24821]: https://github.com/dart-lang/sdk/issues/24821
