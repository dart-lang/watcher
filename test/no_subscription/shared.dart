// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

import '../utils.dart';

void sharedTests() {
  test('does not notify for changes when there are no subscribers', () async {
    // Note that this test doesn't rely as heavily on the test functions in
    // utils.dart because it needs to be very explicit about when the event
    // stream is and is not subscribed.
    var watcher = createWatcher();
    var queue = new StreamQueue(watcher.events);

    // Subscribe to the events.
    var completer = new Completer();
    queue.next.then((event) {
      expect(event.type, ChangeType.ADD);
      expect(event.path.contains("file.txt"), isTrue);
      completer.complete();
    });

    await watcher.ready;

    writeFile('file.txt');

    // Then wait until we get an event for it.
    await completer.future;

    // Unsubscribe.
    await queue.cancel();

    // Now write a file while we aren't listening.
    writeFile("unwatched.txt");

    queue = new StreamQueue(watcher.events);
    queue.next.then((event) {
      // We should get an event for the third file, not the one added while
      // we weren't subscribed.
      expect(event.type, ChangeType.ADD);
      expect(event.path.contains("added.txt"), isTrue);
      completer.complete();
    });

    completer = new Completer();

    // Wait until the watcher is ready to dispatch events again.
    await watcher.ready;

    // And add a third file.
    writeFile("added.txt");

    // Wait until we get an event for the third file.
    await completer.future;
  });
}
