import 'dart:async';

import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

import 'utils.dart';

void main() {
  _MemFs memFs;
  final defaultFactoryId = 'MemFs';

  setUp(() {
    memFs = _MemFs();
    registerCustomWatcherFactory(_MemFsWatcherFactory(defaultFactoryId, memFs));
  });

  tearDown(() async {
    unregisterCustomWatcherFactory(defaultFactoryId);
  });

  test('notifes for files', () async {
    var watcher = FileWatcher('file.txt');

    var completer = Completer<WatchEvent>();
    watcher.events.listen((event) => completer.complete(event));
    await watcher.ready;
    memFs.add('file.txt');
    var event = await completer.future;

    expect(event.type, ChangeType.ADD);
    expect(event.path, 'file.txt');
  });

  test('notifes for directories', () async {
    var watcher = DirectoryWatcher('dir');

    var completer = Completer<WatchEvent>();
    watcher.events.listen((event) => completer.complete(event));
    await watcher.ready;
    memFs.add('dir');
    var event = await completer.future;

    expect(event.type, ChangeType.ADD);
    expect(event.path, 'dir');
  });

  test('unregister works', () async {
    unregisterCustomWatcherFactory(defaultFactoryId);

    watcherFactory = (path) => FileWatcher(path);
    try {
      // This uses standard files, so it wouldn't trigger an event in
      // _MemFsWatcher.
      writeFile('file.txt');
      await startWatcher(path: 'file.txt');
      deleteFile('file.txt');
    } finally {
      watcherFactory = null;
    }

    await expectRemoveEvent('file.txt');
  });

  test('registering twice throws', () async {
    expect(
        () => registerCustomWatcherFactory(
            _MemFsWatcherFactory(defaultFactoryId, memFs)),
        throwsA(isA<ArgumentError>()));
  });

  test('finding two applicable factories throws', () async {
    // Note that _MemFsWatcherFactory always returns a watcher, so having two
    // will always produce a conflict.
    registerCustomWatcherFactory(_MemFsWatcherFactory('Different id', memFs));
    expect(() => FileWatcher('file.txt'), throwsA(isA<StateError>()));
    expect(() => DirectoryWatcher('dir'), throwsA(isA<StateError>()));
  });
}

class _MemFs {
  final _streams = <String, Set<StreamController<WatchEvent>>>{};

  StreamController<WatchEvent> watchStream(String path) {
    var controller = StreamController<WatchEvent>();
    _streams.putIfAbsent(path, () => {}).add(controller);
    return controller;
  }

  void add(String path) {
    var controllers = _streams[path];
    if (controllers != null) {
      for (var controller in controllers) {
        controller.add(WatchEvent(ChangeType.ADD, path));
      }
    }
  }

  void remove(String path) {
    var controllers = _streams[path];
    if (controllers != null) {
      for (var controller in controllers) {
        controller.add(WatchEvent(ChangeType.REMOVE, path));
      }
    }
  }
}

class _MemFsWatcher implements FileWatcher, DirectoryWatcher, Watcher {
  final String _path;
  final StreamController<WatchEvent> _controller;

  _MemFsWatcher(this._path, this._controller);

  @override
  String get path => _path;

  @override
  String get directory => throw UnsupportedError('directory is not supported');

  @override
  Stream<WatchEvent> get events => _controller.stream;

  @override
  bool get isReady => true;

  @override
  Future<void> get ready async {}
}

class _MemFsWatcherFactory implements CustomWatcherFactory {
  final String id;
  final _MemFs _memFs;
  _MemFsWatcherFactory(this.id, this._memFs);

  @override
  DirectoryWatcher createDirectoryWatcher(String path,
          {Duration pollingDelay}) =>
      _MemFsWatcher(path, _memFs.watchStream(path));

  @override
  FileWatcher createFileWatcher(String path, {Duration pollingDelay}) =>
      _MemFsWatcher(path, _memFs.watchStream(path));
}
