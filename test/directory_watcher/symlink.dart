// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';
import 'package:watcher/src/utils.dart';
import 'package:watcher/watcher.dart';

import '../utils.dart';

void sharedTests() {
  group("linking to a", () {
    test("file", () {
      writeFile("file.txt");

      startWatcher();
      createLink("file.txt", "link");

      expectAddEvent("link");
    });

    test("directory", () {
      writeFile("dir/a.txt");
      writeFile("dir/b.txt");

      startWatcher();
      createLink("dir", "link");

      inAnyOrder([
        isAddEvent("link/a.txt"),
        isAddEvent("link/b.txt")
      ]);
    });
  });

  group("changing a", () {
    test("file", () {
      writeFile("file.txt");
      createLink("file.txt", "link");

      startWatcher();
      writeFile("file.txt", contents: "new");

      inAnyOrder([
        isModifyEvent("file.txt"),
        isModifyEvent("link")
      ]);
    });

    test("newly-linked file", () {
      writeFile("file.txt");

      startWatcher();
      createLink("file.txt", "link");
      expectAddEvent("link");

      writeFile("file.txt", contents: "new");
      inAnyOrder([
        isModifyEvent("file.txt"),
        isModifyEvent("link")
      ]);
    });

    test("directory's file", () {
      writeFile("dir/file.txt");
      createLink("dir", "link");
      copyModificationTime("dir/file.txt", "link/file.txt");

      startWatcher();
      writeFile("dir/file.txt", contents: "new");
      copyModificationTime("dir/file.txt", "link/file.txt");

      inAnyOrder([
        isModifyEvent("dir/file.txt"),
        isModifyEvent("link/file.txt")
      ]);
    });

    test("directory's sub-directory", () {
      writeFile("unwatched/file.txt");
      createDir("watched/dir");
      createLink("watched/dir", "watched/link");

      startWatcher(path: "watched");
      renameDir("unwatched", "watched/dir/subdir");

      inAnyOrder([
        isAddEvent("watched/dir/subdir/file.txt"),
        isAddEvent("watched/link/subdir/file.txt")
      ]);
    });
  });

  group("deleting a", () {
    test("targeted file", () {
      writeFile("file.txt");
      createLink("file.txt", "link");

      startWatcher();
      deleteFile("file.txt");

      inAnyOrder([
        isRemoveEvent("file.txt"),
        isRemoveEvent("link")
      ]);
    });

    test("newly-linked file", () {
      writeFile("file.txt");

      startWatcher();
      createLink("file.txt", "link");
      expectAddEvent("link");

      deleteFile("file.txt");
      inAnyOrder([
        isRemoveEvent("file.txt"),
        isRemoveEvent("link")
      ]);
    });

    test("targeted directory", () {
      writeFile("dir/a.txt");
      writeFile("dir/b.txt");
      createLink("dir", "link");

      startWatcher();
      deleteDir("dir");

      inAnyOrder([
        isRemoveEvent("dir/a.txt"),
        isRemoveEvent("dir/b.txt"),
        isRemoveEvent("link/a.txt"),
        isRemoveEvent("link/b.txt")
      ]);
    });

    test("file in a targeted directory", () {
      writeFile("dir/file.txt");
      createLink("dir", "link");

      startWatcher();
      deleteFile("dir/file.txt");

      inAnyOrder([
        isRemoveEvent("dir/file.txt"),
        isRemoveEvent("link/file.txt")
      ]);
    });

    test("symlink to a file", () {
      writeFile("file.txt");
      createLink("file.txt", "link");

      startWatcher();
      deleteLink("link");
      expectRemoveEvent("link");
    });

    test("symlink to a directory", () {
      writeFile("dir/a.txt");
      writeFile("dir/b.txt");
      createLink("dir", "link");

      startWatcher();
      deleteLink("link");

      inAnyOrder([
        isRemoveEvent("link/a.txt"),
        isRemoveEvent("link/b.txt")
      ]);
    });
  });

  group("moving a", () {
    test("targeted file", () {
      writeFile("old.txt");
      createLink("old.txt", "link");

      startWatcher();
      renameFile("old.txt", "new.txt");

      inAnyOrder([
        isRemoveEvent("old.txt"),
        isAddEvent("new.txt"),
        isRemoveEvent("link")
      ]);
    });

    test("targeted directory", () {
      writeFile("old/file.txt");
      createLink("old", "link");

      startWatcher();
      renameDir("old", "new");

      inAnyOrder([
        isRemoveEvent("old/file.txt"),
        isAddEvent("new/file.txt"),
        isRemoveEvent("link/file.txt")
      ]);
    });

    test("subdirectory of a targeted directory", () {
      writeFile("dir/old/file.txt");
      createLink("dir", "link");

      startWatcher();
      renameDir("dir/old", "dir/new");

      inAnyOrder([
        isRemoveEvent("dir/old/file.txt"),
        isAddEvent("dir/new/file.txt"),
        isRemoveEvent("link/old/file.txt"),
        isAddEvent("link/new/file.txt")
      ]);
    });

    test("moving a symlink to a file", () {
      writeFile("file.txt");
      createLink("file.txt", "old");

      startWatcher();
      renameLink("old", "new");

      inAnyOrder([
        isRemoveEvent("old"),
        isAddEvent("new")
      ]);
    });

    test("moving a symlink to a directory", () {
      writeFile("dir/file.txt");
      createLink("dir", "old");

      startWatcher();
      renameLink("old", "new");

      inAnyOrder([
        isRemoveEvent("old/file.txt"),
        isAddEvent("new/file.txt")
      ]);
    });

    test("moving a symlink that was a file so that it's now a directory", () {
      writeFile("entity/file.txt");
      writeFile("dir/entity");
      createLink("entity", "dir/link", relative: true);

      startWatcher();
      renameLink("dir/link", "link");

      inAnyOrder([
        isRemoveEvent("dir/link"),
        isAddEvent("link/file.txt")
      ]);
    });

    test("moving a symlink that was a directory so that it's now a file", () {
      writeFile("entity/file.txt");
      writeFile("dir/entity");
      createLink("entity", "link", relative: true);

      startWatcher();
      renameLink("link", "dir/link");

      inAnyOrder([
        isRemoveEvent("link/file.txt"),
        isAddEvent("dir/link")
      ]);
    });
  });

  // We don't provide any guarantees about broken link behavior, but this
  // shouldn't break.
  test("creating a broken link", () {
    startWatcher();
    createLink("nonexistent", "broken");

    // Write a file and get an event to ensure that the watcher is actually
    // doing something.
    writeFile("file.txt");
    inAnyOrder([
      isAddEvent("file.txt")
    ]);
  });
}
