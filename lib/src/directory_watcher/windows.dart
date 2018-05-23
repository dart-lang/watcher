// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// TODO(rnystrom): Merge with mac_os version.

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../constructable_file_system_event.dart';
import '../directory_watcher.dart';
import '../path_set.dart';
import '../resubscribable.dart';
import '../utils.dart';
import '../watch_event.dart';

class WindowsDirectoryWatcher extends ResubscribableWatcher
    implements DirectoryWatcher {
  String get directory => path;

  WindowsDirectoryWatcher(String directory)
      : super(directory, () => new _WindowsDirectoryWatcher(directory));
}

class _EventBatcher {
  static const Duration _BATCH_DELAY = const Duration(milliseconds: 100);
  final List<FileSystemEvent> events = [];
  Timer timer;

  void addEvent(FileSystemEvent event, void callback()) {
    events.add(event);
    if (timer != null) {
      timer.cancel();
    }
    timer = new Timer(_BATCH_DELAY, callback);
  }

  void cancelTimer() {
    timer.cancel();
  }
}

class _WindowsDirectoryWatcher
    implements DirectoryWatcher, ManuallyClosedWatcher {
  String get directory => path;
  final String path;

  Stream<WatchEvent> get events => _eventsController.stream;
  final _eventsController = new StreamController<WatchEvent>.broadcast();

  bool get isReady => _readyCompleter.isCompleted;

  Future get ready => _readyCompleter.future;
  final _readyCompleter = new Completer();

  final Map<String, _EventBatcher> _eventBatchers =
      new HashMap<String, _EventBatcher>();

  /// The set of files that are known to exist recursively within the watched
  /// directory.
  ///
  /// The state of files on the filesystem is compared against this to determine
  /// the real change that occurred. This is also used to emit REMOVE events
  /// when subdirectories are moved out of the watched directory.
  final PathSet _files;

  /// The subscription to the stream returned by [Directory.watch].
  StreamSubscription<FileSystemEvent> _watchSubscription;

  /// The subscription to the stream returned by [Directory.watch] of the
  /// parent directory to [directory]. This is needed to detect changes to
  /// [directory], as they are not included on Windows.
  StreamSubscription<FileSystemEvent> _parentWatchSubscription;

  /// The subscription to the [Directory.list] call for the initial listing of
  /// the directory to determine its initial state.
  StreamSubscription<FileSystemEntity> _initialListSubscription;

  /// The subscriptions to the [Directory.list] calls for listing the contents
  /// of subdirectories that were moved into the watched directory.
  final Set<StreamSubscription<FileSystemEntity>> _listSubscriptions =
      new HashSet<StreamSubscription<FileSystemEntity>>();

  _WindowsDirectoryWatcher(String path)
      : path = path,
        _files = new PathSet(path) {
    // Before we're ready to emit events, wait for [_listDir] to complete.
    _listDir().then((_) {
      _startWatch();
      _startParentWatcher();
      _readyCompleter.complete();
    });
  }

  void close() {
    if (_watchSubscription != null) _watchSubscription.cancel();
    if (_parentWatchSubscription != null) _parentWatchSubscription.cancel();
    if (_initialListSubscription != null) _initialListSubscription.cancel();
    for (var sub in _listSubscriptions) {
      sub.cancel();
    }
    _listSubscriptions.clear();
    for (var batcher in _eventBatchers.values) {
      batcher.cancelTimer();
    }
    _eventBatchers.clear();
    _watchSubscription = null;
    _parentWatchSubscription = null;
    _initialListSubscription = null;
    _eventsController.close();
  }

  /// On Windows, if [directory] is deleted, we will not receive any event.
  ///
  /// Instead, we add a watcher on the parent folder (if any), that can notify
  /// us about [path]. This also includes events such as moves.
  void _startParentWatcher() {
    var absoluteDir = p.absolute(path);
    var parent = p.dirname(absoluteDir);
    // Check if [path] is already the root directory.
    if (FileSystemEntity.identicalSync(parent, path)) return;
    var parentStream = new Directory(parent).watch(recursive: false);
    _parentWatchSubscription = parentStream.listen((event) {
      // Only look at events for 'directory'.
      if (p.basename(event.path) != p.basename(absoluteDir)) return;
      // Test if the directory is removed. FileSystemEntity.typeSync will
      // return NOT_FOUND if it's unable to decide upon the type, including
      // access denied issues, which may happen when the directory is deleted.
      // FileSystemMoveEvent and FileSystemDeleteEvent events will always mean
      // the directory is now gone.
      if (event is FileSystemMoveEvent ||
          event is FileSystemDeleteEvent ||
          (FileSystemEntity.typeSync(path) == FileSystemEntityType.NOT_FOUND)) {
        for (var path in _files.paths) {
          _emitEvent(ChangeType.REMOVE, path);
        }
        _files.clear();
        close();
      }
    }, onError: (error) {
      // Ignore errors, simply close the stream. The user listens on
      // [directory], and while it can fail to listen on the parent, we may
      // still be able to listen on the path requested.
      _parentWatchSubscription.cancel();
      _parentWatchSubscription = null;
    });
  }

  void _onEvent(FileSystemEvent event) {
    assert(isReady);
    final batcher =
        _eventBatchers.putIfAbsent(event.path, () => new _EventBatcher());
    batcher.addEvent(event, () {
      _eventBatchers.remove(event.path);
      _onBatch(batcher.events);
    });
  }

  /// The callback that's run when [Directory.watch] emits a batch of events.
  void _onBatch(List<FileSystemEvent> batch) {
    _sortEvents(batch).forEach((path, eventSet) {
      var canonicalEvent = _canonicalEvent(eventSet);
      var events = canonicalEvent == null
          ? _eventsBasedOnFileSystem(path)
          : [canonicalEvent];

      for (var event in events) {
        if (event is FileSystemCreateEvent) {
          if (!event.isDirectory) {
            if (_files.contains(path)) continue;

            _emitEvent(ChangeType.ADD, path);
            _files.add(path);
            continue;
          }

          if (_files.containsDir(path)) continue;

          var stream = new Directory(path).list(recursive: true);
          StreamSubscription<FileSystemEntity> subscription;
          subscription = stream.listen((entity) {
            if (entity is Directory) return;
            if (_files.contains(path)) return;

            _emitEvent(ChangeType.ADD, entity.path);
            _files.add(entity.path);
          }, onDone: () {
            _listSubscriptions.remove(subscription);
          }, onError: (e, stackTrace) {
            _listSubscriptions.remove(subscription);
            _emitError(e, stackTrace);
          }, cancelOnError: true);
          _listSubscriptions.add(subscription);
        } else if (event is FileSystemModifyEvent) {
          if (!event.isDirectory) {
            _emitEvent(ChangeType.MODIFY, path);
          }
        } else {
          assert(event is FileSystemDeleteEvent);
          for (var removedPath in _files.remove(path)) {
            _emitEvent(ChangeType.REMOVE, removedPath);
          }
        }
      }
    });
  }

  /// Sort all the events in a batch into sets based on their path.
  ///
  /// A single input event may result in multiple events in the returned map;
  /// for example, a MOVE event becomes a DELETE event for the source and a
  /// CREATE event for the destination.
  ///
  /// The returned events won't contain any [FileSystemMoveEvent]s, nor will it
  /// contain any events relating to [path].
  Map<String, Set<FileSystemEvent>> _sortEvents(List<FileSystemEvent> batch) {
    var eventsForPaths = <String, Set<FileSystemEvent>>{};

    // Events within directories that already have events are superfluous; the
    // directory's full contents will be examined anyway, so we ignore such
    // events. Emitting them could cause useless or out-of-order events.
    var directories = unionAll(batch.map((event) {
      if (!event.isDirectory) return new Set<String>();
      if (event is FileSystemMoveEvent) {
        return new Set<String>.from([event.path, event.destination]);
      }
      return new Set<String>.from([event.path]);
    }));

    isInModifiedDirectory(String path) =>
        directories.any((dir) => path != dir && path.startsWith(dir));

    addEvent(String path, FileSystemEvent event) {
      if (isInModifiedDirectory(path)) return;
      eventsForPaths
          .putIfAbsent(path, () => new Set<FileSystemEvent>())
          .add(event);
    }

    for (var event in batch) {
      if (event is FileSystemMoveEvent) {
        addEvent(event.destination, event);
      }
      addEvent(event.path, event);
    }

    return eventsForPaths;
  }

  /// Returns the canonical event from a batch of events on the same path, if
  /// one exists.
  ///
  /// If [batch] doesn't contain any contradictory events (e.g. DELETE and
  /// CREATE, or events with different values for [isDirectory]), this returns a
  /// single event that describes what happened to the path in question.
  ///
  /// If [batch] does contain contradictory events, this returns `null` to
  /// indicate that the state of the path on the filesystem should be checked to
  /// determine what occurred.
  FileSystemEvent _canonicalEvent(Set<FileSystemEvent> batch) {
    // An empty batch indicates that we've learned earlier that the batch is
    // contradictory (e.g. because of a move).
    if (batch.isEmpty) return null;

    var type = batch.first.type;
    var isDir = batch.first.isDirectory;

    for (var event in batch.skip(1)) {
      // If one event reports that the file is a directory and another event
      // doesn't, that's a contradiction.
      if (isDir != event.isDirectory) return null;

      // Modify events don't contradict either CREATE or REMOVE events. We can
      // safely assume the file was modified after a CREATE or before the
      // REMOVE; otherwise there will also be a REMOVE or CREATE event
      // (respectively) that will be contradictory.
      if (event is FileSystemModifyEvent) continue;
      assert(event is FileSystemCreateEvent ||
          event is FileSystemDeleteEvent ||
          event is FileSystemMoveEvent);

      // If we previously thought this was a MODIFY, we now consider it to be a
      // CREATE or REMOVE event. This is safe for the same reason as above.
      if (type == FileSystemEvent.MODIFY) {
        type = event.type;
        continue;
      }

      // A CREATE event contradicts a REMOVE event and vice versa.
      assert(type == FileSystemEvent.CREATE ||
          type == FileSystemEvent.DELETE ||
          type == FileSystemEvent.MOVE);
      if (type != event.type) return null;
    }

    switch (type) {
      case FileSystemEvent.CREATE:
        return new ConstructableFileSystemCreateEvent(batch.first.path, isDir);
      case FileSystemEvent.DELETE:
        return new ConstructableFileSystemDeleteEvent(batch.first.path, isDir);
      case FileSystemEvent.MODIFY:
        return new ConstructableFileSystemModifyEvent(
            batch.first.path, isDir, false);
      case FileSystemEvent.MOVE:
        return null;
      default:
        throw 'unreachable';
    }
  }

  /// Returns one or more events that describe the change between the last known
  /// state of [path] and its current state on the filesystem.
  ///
  /// This returns a list whose order should be reflected in the events emitted
  /// to the user, unlike the batched events from [Directory.watch]. The
  /// returned list may be empty, indicating that no changes occurred to [path]
  /// (probably indicating that it was created and then immediately deleted).
  List<FileSystemEvent> _eventsBasedOnFileSystem(String path) {
    var fileExisted = _files.contains(path);
    var dirExisted = _files.containsDir(path);
    var fileExists = new File(path).existsSync();
    var dirExists = new Directory(path).existsSync();

    var events = <FileSystemEvent>[];
    if (fileExisted) {
      if (fileExists) {
        events.add(new ConstructableFileSystemModifyEvent(path, false, false));
      } else {
        events.add(new ConstructableFileSystemDeleteEvent(path, false));
      }
    } else if (dirExisted) {
      if (dirExists) {
        // If we got contradictory events for a directory that used to exist and
        // still exists, we need to rescan the whole thing in case it was
        // replaced with a different directory.
        events.add(new ConstructableFileSystemDeleteEvent(path, true));
        events.add(new ConstructableFileSystemCreateEvent(path, true));
      } else {
        events.add(new ConstructableFileSystemDeleteEvent(path, true));
      }
    }

    if (!fileExisted && fileExists) {
      events.add(new ConstructableFileSystemCreateEvent(path, false));
    } else if (!dirExisted && dirExists) {
      events.add(new ConstructableFileSystemCreateEvent(path, true));
    }

    return events;
  }

  /// The callback that's run when the [Directory.watch] stream is closed.
  /// Note that this is unlikely to happen on Windows, unless the system itself
  /// closes the handle.
  void _onDone() {
    _watchSubscription = null;

    // Emit remove events for any remaining files.
    for (var file in _files.paths) {
      _emitEvent(ChangeType.REMOVE, file);
    }
    _files.clear();
    close();
  }

  /// Start or restart the underlying [Directory.watch] stream.
  void _startWatch() {
    // Batch the events together so that we can dedup events.
    var innerStream = new Directory(path).watch(recursive: true);
    _watchSubscription = innerStream.listen(_onEvent,
        onError: _eventsController.addError, onDone: _onDone);
  }

  /// Starts or restarts listing the watched directory to get an initial picture
  /// of its state.
  Future _listDir() {
    assert(!isReady);
    if (_initialListSubscription != null) _initialListSubscription.cancel();

    _files.clear();
    var completer = new Completer();
    var stream = new Directory(path).list(recursive: true);
    void handleEntity(entity) {
      if (entity is! Directory) _files.add(entity.path);
    }

    _initialListSubscription = stream.listen(handleEntity,
        onError: _emitError, onDone: completer.complete, cancelOnError: true);
    return completer.future;
  }

  /// Emit an event with the given [type] and [path].
  void _emitEvent(ChangeType type, String path) {
    if (!isReady) return;

    _eventsController.add(new WatchEvent(type, path));
  }

  /// Emit an error, then close the watcher.
  void _emitError(error, StackTrace stackTrace) {
    _eventsController.addError(error, stackTrace);
    close();
  }
}
