// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

import 'symlink.dart';
import '../utils.dart';

void main() {
  // Use a short delay to make the tests run quickly.
  watcherFactory = (dir) => new PollingDirectoryWatcher(dir,
      pollingDelay: new Duration(milliseconds: 100));

  sharedTests();
}
