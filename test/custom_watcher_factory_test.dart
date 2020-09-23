import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

void main() {
  _MemFs memFs;

  setUp(() {
    memFs = _MemFs();
    registerCustomWatcherFactory(_MemFsWatcherFactory(memFs));
  });

  tearDown(() async {
    unregisterCustomWatcherFactory('MemFs');
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
    var memFactory = _MemFsWatcherFactory(memFs);
    unregisterCustomWatcherFactory(memFactory.id);

    var completer = Completer<dynamic>();
    var watcher = FileWatcher('file.txt');
    watcher.events.listen((e) {}, onError: (e) => completer.complete(e));
    await watcher.ready;
    memFs.add('file.txt');
    var result = await completer.future;

    expect(result, isA<FileSystemException>());
  });

  test('registering twice throws', () async {
    expect(() => registerCustomWatcherFactory(_MemFsWatcherFactory(memFs)),
        throwsA(isA<ArgumentError>()));
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
  final _MemFs _memFs;
  _MemFsWatcherFactory(this._memFs);

  @override
  String get id => 'MemFs';

  @override
  DirectoryWatcher createDirectoryWatcher(String path,
          {Duration pollingDelay}) =>
      _MemFsWatcher(path, _memFs.watchStream(path));

  @override
  FileWatcher createFileWatcher(String path, {Duration pollingDelay}) =>
      _MemFsWatcher(path, _memFs.watchStream(path));
}
