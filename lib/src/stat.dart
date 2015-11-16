// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library watcher.stat;

import 'dart:async';
import 'dart:io';

/// A function that takes a file path and returns the last modified time for
/// the file at that path.
typedef DateTime MockTimeCallback(String path);

MockTimeCallback _mockTimeCallback;

/// Overrides the default behavior for accessing a file's modification time
/// with [callback].
///
/// The OS file modification time has pretty rough granularity (like a few
/// seconds) which can make for slow tests that rely on modtime. This lets you
/// replace it with something you control.
void mockGetModificationTime(MockTimeCallback callback) {
  _mockTimeCallback = callback;
}

/// Gets the modification time for the file at [path].
///
/// Due to sdk#24821, for symlinks this is always the modification time of the
/// final target of the link.
Future<DateTime> getModificationTime(String path) async {
  if (_mockTimeCallback != null) {
    if (await FileSystemEntity.isLink(path)) {
      path = await new Link(path).resolveSymbolicLinks();
    }

    return _mockTimeCallback(path);
  }

  return (await FileStat.stat(path)).modified;
}
