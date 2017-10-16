// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import '../directory_watcher.dart';
import '../entity.dart';
import '../native_watcher.dart';
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
  final NativeWatcher _nativeWatcher;

  /// All known files recursively within [path].
  final PathSet _files;

  /// A set of all subscriptions that this watcher subscribes to.
  ///
  /// These are gathered together so that they may all be canceled when the
  /// watcher is closed.
  final _subscriptions = new Set<StreamSubscription>();

  _LinuxDirectoryWatcher(String path)
      : _files = new PathSet(path),
        _nativeWatcher = new NativeWatcher(path) {
    _listen(_nativeWatcher.events, _onBatch,
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
    _files.clear();
    _eventsController.close();
  }

  /// The callback that's run when a batch of changes comes in.
  void _onBatch(Object data) {
    var batch = data as List<FileSystemEvent>;
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
    // Delete events are simple, since whatever it was is gone now anyway.
    if (event is FileSystemDeleteEvent) return new Entity.removed(event.path);

    // Events that say they're directories are always non-symlink
    // directories.
    if (event.isDirectory) {
      return new Entity(event.path, FileSystemEntityType.DIRECTORY);
    }

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
      _nativeWatcher.remove(path);

      // Unless [path] was a file and still is, emit REMOVE events for it or its
      // contents,
      if (!state.isFile || !_files.contains(path)) {
        for (var file in _files.remove(path)) {
          _nativeWatcher.remove(file);
          _emit(ChangeType.REMOVE, file);
        }
      }

      // If [path] is a directory, watch it and emit events for its contents.
      if (state.isDirectory) {
        _nativeWatcher.watchSubdir(path, isLink: state.isLink);

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
      if (state.isLink) _nativeWatcher.watchSymlinkedFile(path);

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
        _nativeWatcher.watchSubdir(entity.path, isLink: entity.isLink);
      } else {
        _files.add(entity.path);
        if (entity.isLink) _nativeWatcher.watchSymlinkedFile(entity.path);
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
      for (var file in _files.paths) {
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
