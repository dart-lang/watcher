// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('windows')
library;

import 'package:test/test.dart';
import 'package:watcher/src/directory_watcher/windows.dart';

import '../utils.dart';
import 'shared.dart';

void main() {
  watcherFactory = WindowsDirectoryWatcher.new;

  sharedTests();
}
