// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:path/path.dart' as p;

import 'fake_file_system_event.dart';
import 'utils.dart';

/// A thin wrapper around [Directory.watch] that merges and batches event
/// streams for multiple files and directories.
class NativeWatcher {
  /// The root directory being watched.
  ///
  /// All files and subdirectories must be within this.
  final String root;

  /// The merged and batched event stream.
  ///
  /// This emits batches of events so that multiple events happening at once can
  /// be correlated and de-duplicated.
  Stream<List<FileSystemEvent>> get events => _events.stream
      .transform(new BatchedStreamTransformer<FileSystemEvent>());
  final _events = new StreamGroup<FileSystemEvent>();

  /// [Directory.watch] streams for [root]'s subdirectories, indexed by path.
  ///
  /// A stream is in this map if and only if it's also in [_events].
  final _subdirStreams = <String, Stream<FileSystemEvent>>{};

  /// [File.watch] streams for symlinks to files, indexed by path.
  ///
  /// These are needed because a directory doesn't emit an event if it contains
  /// a symlink whose target file is modified. A stream is in this map if and
  /// only if it's also in [_events].
  final _symlinkFileStreams = <String, Stream<FileSystemEvent>>{};

  NativeWatcher(this.root) {
    _events.add(new Directory(root).watch().transform(
        new StreamTransformer.fromHandlers(handleDone: (sink) {
      // Once the root directory is deleted, all the sub-watches should be
      // removed too.
      _events.close();
      _subdirStreams.values.forEach(_events.remove);
      _symlinkFileStreams.values.forEach(_events.remove);
      sink.close();
    })));
  }

  /// Watch a subdirectory of [directory] for changes.
  ///
  /// On Linux, if [isLink] is true, [path] is known to be a symlink and special
  /// behavior is used to work around sdk#24815. On other platforms the
  /// parameter can safely be omitted.
  void watchSubdir(String path, {bool isLink: false}) {
    assert(p.isWithin(root, path));
    assert(!_symlinkFileStreams.containsKey(path));

    // TODO(nweiz): Enable this once #22 is fixed.
    // assert(!_subdirStreams.containsKey(path));

    // TODO(nweiz): Right now it's possible for the watcher to emit an event for
    // a file before the directory list is complete. This could lead to the user
    // seeing a MODIFY or REMOVE event for a file before they see an ADD event,
    // which is bad. We should handle that.
    //
    // One possibility is to provide a general means (e.g.
    // `DirectoryWatcher.eventsAndExistingFiles`) to tell a watcher to emit
    // events for all the files that already exist. This would be useful for
    // top-level clients such as barback as well, and could be implemented with
    // a wrapper similar to how listening/canceling works now.

    // TODO(nweiz): Catch any errors here that indicate that the directory in
    // question doesn't exist and silently stop watching it instead of
    // propagating the errors.

    // TODO(nweiz): Gracefully handle the symlink edge cases described in the
    // README. We could do so with some combination of watching containing
    // directories and polling to see if nonexistent targets start to exist.

    var stream;
    if (isLink && Platform.isLinux) {
      // Work around sdk#24815 by listening to the concrete directory and
      // post-processing the events so they have the paths we expect.
      var resolvedPath = new Link(path).resolveSymbolicLinksSync();
      stream = new Directory(resolvedPath).watch().map((event) =>
          new FakeFileSystemEvent.rebase(event, resolvedPath, path));
    } else {
      stream = new Directory(path).watch();
    }

    _subdirStreams[path] = stream;
    _events.add(stream);
  }

  /// Watch the target of a symlink at [path] that points to a file.
  void watchSymlinkedFile(String path) {
    assert(p.isWithin(root, path));
    assert(!_symlinkFileStreams.containsKey(path));

    // TODO(nweiz): Enable this once #22 is fixed.
    // assert(!_subdirStreams.containsKey(path));

    var stream;
    if (Platform.isLinux) {
      // Work around sdk#24815 by listening to the concrete file and
      // post-processing the events so they have the paths we expect.
      var resolvedPath = new Link(path).resolveSymbolicLinksSync();
      stream = new File(resolvedPath).watch().map((event) {
        return new FakeFileSystemEvent.withPath(event, path);
      });
    } else {
      stream = new File(path).watch();
    }

    _symlinkFileStreams[path] = stream;
    _events.add(stream);
  }

  /// Removes the watch for [path], whether it's a file or a directory.
  void remove(String path) {
    var stream = _subdirStreams.remove(path) ??
        _symlinkFileStreams.remove(path);
    if (stream != null) _events.remove(stream);
  }
}

