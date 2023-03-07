// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('linux || mac-os')
library;

import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

import '../utils.dart';
import 'shared.dart';

void main() {
  watcherFactory = (file) =>
      PollingFileWatcher(file, pollingDelay: Duration(milliseconds: 100));

  setUp(() {
    writeFile('file.txt');
  });

  sharedTests();
}
