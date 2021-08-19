// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('linux || mac-os')

import 'package:test/test.dart';
import 'package:watcher/src/file_watcher.dart';
import 'package:watcher/src/file_watcher/native.dart';
import 'package:watcher/src/file_watcher/polling.dart';

import 'shared.dart';
import '../utils.dart';

void main() {
  watcherFactory = (file) => NativeFileWatcher(file);

  setUp(() {
    writeFile('file.txt');
  });

  test('FileWatcher creates a NativeFileWatcher on supported platform', () {
    expect(FileWatcher('file.txt'), TypeMatcher<NativeFileWatcher>());
  });

  test('FileWatcher creates a PollingFileWatcher when forced', () {
    expect(FileWatcher('file.txt', forcePollingWatcher: true),
        TypeMatcher<PollingFileWatcher>());
  });

  sharedTests();
}
