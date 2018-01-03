// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('linux || mac-os')

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:watcher/src/stat.dart';
import 'package:watcher/watcher.dart';

import 'shared.dart';
import '../utils.dart';

void main() {
  watcherFactory = (file) => new PollingFileWatcher(file,
      pollingDelay: new Duration(milliseconds: 100));

  /// The mock modification times (in milliseconds since epoch) for each file.
  ///
  /// The actual file system has pretty coarse granularity for file modification
  /// times. This means using the real file system requires us to put delays in
  /// the tests to ensure we wait long enough between operations for the mod time
  /// to be different.
  ///
  /// Instead, we'll just mock that out. Each time a file is written, we manually
  /// increment the mod time for that file instantly.
  Map<String, int> _mockFileModificationTimes;

  setUp(() {
    _mockFileModificationTimes = new Map<String, int>();

    mockGetModificationTime((path) {
      path = p.normalize(p.relative(path, from: d.sandbox));

      // Make sure we got a path in the sandbox.
      assert(p.isRelative(path) && !path.startsWith(".."));

      var mtime = _mockFileModificationTimes[path];
      return new DateTime.fromMillisecondsSinceEpoch(mtime == null ? 0 : mtime);
    });
    writeFile("file.txt");
  });

  sharedTests();
}
