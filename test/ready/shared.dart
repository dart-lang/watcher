// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../utils.dart';

void sharedTests() {
  test('ready does not complete until after subscription', () async {
    var watcher = createWatcher();

    // Should not be ready yet.
    expect(watcher.isReady, isFalse);

    // Subscribe to the events.
    watcher.events.listen((event) {});

    // Should eventually be ready.
    await watcher.ready;

    expect(watcher.isReady, isTrue);
  });

  test('ready completes immediately when already ready', () async {
    var watcher = createWatcher();

    // Subscribe to the events.
    watcher.events.listen((event) {});

    // Should eventually be ready.
    await watcher.ready;

    expect(watcher.isReady, isTrue);
  });

  test('ready returns a future that does not complete after unsubscribing',
      () async {
    var watcher = createWatcher();

    // Subscribe to the events.
    var subscription = watcher.events.listen((event) {});

    var ready = false;

    // Wait until ready.
    await watcher.ready;

    // Now unsubscribe.
    await subscription.cancel();

    // Track when it's ready again.
    ready = false;
    watcher.ready.then((_) {
      ready = true;
    });

    // Should be back to not ready.
    expect(ready, isFalse);
  });
}
