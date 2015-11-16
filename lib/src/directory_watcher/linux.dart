// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library watcher.directory_watcher.linux;

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';

import '../directory_watcher.dart';
import '../entity.dart';
import '../fake_file_system_event.dart';
import '../path_set.dart';
import '../resubscribable.dart';
import '../utils.dart';
import '../watch_event.dart';

/// Uses the inotify subsystem to watch for filesystem events.
///
/// Inotify doesn't suport recursively watching subdirectories, nor does
/// [Directory.watch] polyfill that functionality. This class polyfills it
/// instead. It also polyfills following symlinks, which inotify supports but
/// isn't exposed via `Directory.watch`.
///
/// This class also compensates for the non-inotify-specific issues of
/// [Directory.watch] producing multiple events for a single logical action
/// (issue 14372) and providing insufficient information about move events
/// (issue 14424).
class LinuxDirectoryWatcher extends ResubscribableWatcher
    implements DirectoryWatcher {
  String get directory => path;

  LinuxDirectoryWatcher(String directory)
      : super(directory, () => new _LinuxDirectoryWatcher(directory));
}

class _LinuxDirectoryWatcher
    implements DirectoryWatcher, ManuallyClosedWatcher {
  String get directory => _files.root;
  String get path => _files.root;

  Stream<WatchEvent> get events => _eventsController.stream;
  final _eventsController = new StreamController<WatchEvent>.broadcast();

  bool get isReady => _readyCompleter.isCompleted;

  Future get ready => _readyCompleter.future;
  final _readyCompleter = new Completer();

  /// A stream group for the [Directory.watch] events of [path] and all its
  /// subdirectories.
  var _nativeEvents = new StreamGroup<FileSystemEvent>();

  /// All known files recursively within [path].
  final PathSet _files;

  /// [Directory.watch] streams for [path]'s subdirectories, indexed by path.
  ///
  /// A stream is in this map if and only if it's also in [_nativeEvents].
  final _subdirStreams = <String, Stream<FileSystemEvent>>{};

  /// [File.watch] streams for symlinks to files, indexed by path.
  ///
  /// These are needed because a directory doesn't emit an event if it contains
  /// a symlink whose target file is modified. A stream is in this map if and
  /// only if it's also in [_nativeEvents].
  final _symlinkFileStreams = <String, Stream<FileSystemEvent>>{};

  /// A set of all subscriptions that this watcher subscribes to.
  ///
  /// These are gathered together so that they may all be canceled when the
  /// watcher is closed.
  final _subscriptions = new Set<StreamSubscription>();

  _LinuxDirectoryWatcher(String path)
      : _files = new PathSet(path) {
    _nativeEvents.add(new Directory(path).watch().transform(
        new StreamTransformer.fromHandlers(handleDone: (sink) {
      // Once the root directory is deleted, no more new subdirectories will be
      // watched.
      _nativeEvents.close();
      sink.close();
    })));

    // Batch the inotify changes together so that we can dedup events.
    var innerStream = _nativeEvents.stream
        .transform(new BatchedStreamTransformer<FileSystemEvent>());
    _listen(innerStream, _onBatch,
        onError: _eventsController.addError,
        onDone: _onDone);

    _checkContents(path, onError: (error, stackTrace) {
      _eventsController.addError(error, stackTrace);
      close();
    }, onDone: () {
      _readyCompleter.complete();
    });
  }

  void close() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }

    _subscriptions.clear();
    _subdirStreams.clear();
    _symlinkFileStreams.clear();
    _files.clear();
    _nativeEvents.close();
    _eventsController.close();
  }

  /// Watch a subdirectory of [directory] for changes.
  ///
  /// If [isLink] is true, [path] is known to be a symlink and special behavior
  /// is used to work around sdk#24815.
  void _watchSubdir(String path, {bool isLink: false}) {
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
    if (isLink) {
      // Work around sdk#24815 by listening to the concrete directory and
      // post-processing the events so they have the paths we expect.
      var resolvedPath = new Link(path).resolveSymbolicLinksSync();
      stream = new Directory(resolvedPath).watch().map((event) =>
          new FakeFileSystemEvent.rebase(event, resolvedPath, path));
    } else {
      stream = new Directory(path).watch();
    }

    _subdirStreams[path] = stream;
    _nativeEvents.add(stream);
  }

  /// Watch the target of a symlink at [path] that points to a file.
  void _watchSymlink(String path) {
    // Work around sdk#24815 by listening to the concrete file and
    // post-processing the events so they have the paths we expect.
    var resolvedPath = new Link(path).resolveSymbolicLinksSync();
    var stream = new File(resolvedPath).watch().map((event) {
      return new FakeFileSystemEvent.withPath(event, path);
    });
    _symlinkFileStreams[path] = stream;
    _nativeEvents.add(stream);
  }

  /// The callback that's run when a batch of changes comes in.
  void _onBatch(List<FileSystemEvent> batch) {
    var changes = <String, Entity>{};

    // inotify event batches are ordered by occurrence, so we treat them as a
    // log of what happened to a file. We only emit events based on the
    // difference between the state before the batch and the state after it, not
    // the intermediate state.
    for (var event in batch) {
      // If the watched directory is deleted or moved, we'll get a deletion
      // event for it. Ignore it; we handle closing [this] when the underlying
      // stream is closed.
      if (event.path == path) continue;

      var state = _stateFor(event);
      if (event is FileSystemMoveEvent) {
        changes[event.path] = new Entity.removed(path);
        changes[event.destination] = state;
      } else {
        changes[event.path] = state;
      }
    }

    _applyChanges(changes);
  }

  /// Returns the [Entity] representing the result of [event].
  ///
  /// This represents the current state of [event.path], except for a move
  /// event, for which it represents the state of [event.destination].
  Entity _stateFor(FileSystemEvent event) {
    // Events that say they're directories are always non-symlink
    // directories.
    if (event.isDirectory) {
      return new Entity(event.path, FileSystemEntityType.DIRECTORY);
    }

    // Delete events are simple, since whatever it was is gone now anyway.
    if (event is FileSystemDeleteEvent) return new Entity.removed(event.path);

    // For create, modify, and move events we need to check an actual entity
    // on disk.
    var path =
        event is FileSystemMoveEvent ? event.destination : event.path;

    // If it's not a link, then [event.isDirectory] is accurate. We
    // checked it before, so here we know this must be a file.
    if (!FileSystemEntity.isLinkSync(path)) {
      return new Entity(path, FileSystemEntityType.FILE);
    }

    return new Entity(path, FileSystemEntity.typeSync(path), isLink: true);
  }

  /// Applies the net [changes] computed for a batch.
  void _applyChanges(Map<String, Entity> changes) {
    changes.forEach((path, state) {
      var stream = _subdirStreams.remove(path) ??
          _symlinkFileStreams.remove(path);
      if (stream != null) _nativeEvents.remove(stream);

      // Unless [path] was a file and still is, emit REMOVE events for it or its
      // contents,
      if (!state.isFile || !_files.contains(path)) {
        for (var file in _files.remove(path)) {
          _emit(ChangeType.REMOVE, file);
        }
      }

      // If [path] is a directory, watch it and emit events for its contents.
      if (state.isDirectory) {
        _watchSubdir(path, isLink: state.isLink);

        _checkContents(path, onFile: (entity) {
          _emit(ChangeType.ADD, entity.path);
        }, onError: (error, stackTrace) {
          // Ignore an exception caused by the dir not existing. It's fine if it
          // was added and then quickly removed.
          if (error is FileSystemException) return;

          _eventsController.addError(error, stackTrace);
          close();
        });
        return;
      }

      // If [path] was removed or is a broken symlink, do nothing.
      if (!state.isFile) return;

      // If [path] is a valid symlink to a file, watch it because otherwise we
      // won't get events for its contents changing.
      if (state.isLink) _watchSymlink(path);

      // Emit an event for [path] itself being changed or added.
      if (_files.contains(path)) {
        _emit(ChangeType.MODIFY, path);
      } else {
        _emit(ChangeType.ADD, path);
        _files.add(path);
      }
    });
  }

  /// Recursively adds the contents of [path] to [_files].
  ///
  /// This also watches any subdirectories or symlinked files in [path] for
  /// further events.
  ///
  /// If [onFile] is passed, this calls it for every file it traverses. If
  /// [onError] and/or [onDone] are passed, they're forwarded to
  /// [Stream.listen].
  void _checkContents(String path, {void onFile(Entity entity),
      void onError(error, StackTrace stackTrace), void onDone()}) {
    _listen(listDirThroughLinks(path), (entity) {
      if (entity.type == FileSystemEntityType.DIRECTORY) {
        _watchSubdir(entity.path, isLink: entity.isLink);
      } else {
        _files.add(entity.path);
        if (entity.isLink) _watchSymlink(entity.path);
        if (onFile != null) onFile(entity);
      }
    }, onError: onError, onDone: onDone, cancelOnError: true);
  }

  /// Handles the underlying event stream closing, indicating that the directory
  /// being watched was removed.
  void _onDone() {
    // Most of the time when a directory is removed, its contents will get
    // individual REMOVE events before the watch stream is closed -- in that
    // case, [_files] will be empty here. However, if the directory's removal is
    // caused by a MOVE, we need to manually emit events.
    if (isReady) {
      for (var file in _files) {
        _emit(ChangeType.REMOVE, file);
      }
    }

    close();
  }

  /// Emits a [WatchEvent] with [type] and [path] if this watcher is in a state
  /// to emit events.
  void _emit(ChangeType type, String path) {
    if (!isReady) return;
    if (_eventsController.isClosed) return;
    _eventsController.add(new WatchEvent(type, path));
  }

  /// Like [Stream.listen], but automatically adds the subscription to
  /// [_subscriptions] so that it can be canceled when [close] is called.
  void _listen(Stream stream, void onData(event), {Function onError,
      void onDone(), bool cancelOnError}) {
    var subscription;
    subscription = stream.listen(onData, onError: onError, onDone: () {
      _subscriptions.remove(subscription);
      if (onDone != null) onDone();
    }, cancelOnError: cancelOnError);
    _subscriptions.add(subscription);
  }
}
