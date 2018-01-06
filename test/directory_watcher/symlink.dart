// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../utils.dart';

void sharedTests() {
  group("linking to a", () {
    test("file", () async {
      writeFile("file.txt");

      await startWatcher();
      createLink("file.txt", "link");

      await expectAddEvent("link");
    });

    test("directory", () async {
      writeFile("dir/a.txt");
      writeFile("dir/b.txt");

      await startWatcher();
      createLink("dir", "link");

      await inAnyOrder([isAddEvent("link/a.txt"), isAddEvent("link/b.txt")]);
    });
  });

  group("changing a", () {
    test("file", () async {
      writeFile("file.txt");
      createLink("file.txt", "link");

      await startWatcher();
      writeFile("file.txt", contents: "new");

      await inAnyOrder([isModifyEvent("file.txt"), isModifyEvent("link")]);
    });

    test("newly-linked file", () async {
      writeFile("file.txt");

      await startWatcher();
      createLink("file.txt", "link");
      await expectAddEvent("link");

      writeFile("file.txt", contents: "new");
      await inAnyOrder([isModifyEvent("file.txt"), isModifyEvent("link")]);
    });

    test("directory's file", () async {
      writeFile("dir/file.txt");
      createLink("dir", "link");
      copyModificationTime("dir/file.txt", "link/file.txt");

      await startWatcher();
      writeFile("dir/file.txt", contents: "new");
      copyModificationTime("dir/file.txt", "link/file.txt");

      await inAnyOrder(
          [isModifyEvent("dir/file.txt"), isModifyEvent("link/file.txt")]);
    });

    test("directory's sub-directory", () async {
      writeFile("unwatched/file.txt");
      createDir("watched/dir");
      createLink("watched/dir", "watched/link");

      await startWatcher(path: "watched");
      renameDir("unwatched", "watched/dir/subdir");

      await inAnyOrder([
        isAddEvent("watched/dir/subdir/file.txt"),
        isAddEvent("watched/link/subdir/file.txt")
      ]);
    });
  });

  group("deleting a", () {
    test("targeted file", () async {
      writeFile("file.txt");
      createLink("file.txt", "link");

      await startWatcher();
      deleteFile("file.txt");

      await inAnyOrder([isRemoveEvent("file.txt"), isRemoveEvent("link")]);
    });

    test("newly-linked file", () async {
      writeFile("file.txt");

      await startWatcher();
      createLink("file.txt", "link");
      await expectAddEvent("link");

      deleteFile("file.txt");
      await inAnyOrder([isRemoveEvent("file.txt"), isRemoveEvent("link")]);
    });

    test("targeted directory", () async {
      writeFile("dir/a.txt");
      writeFile("dir/b.txt");
      createLink("dir", "link");

      await startWatcher();
      deleteDir("dir");

      await inAnyOrder([
        isRemoveEvent("dir/a.txt"),
        isRemoveEvent("dir/b.txt"),
        isRemoveEvent("link/a.txt"),
        isRemoveEvent("link/b.txt")
      ]);
    });

    test("file in a targeted directory", () async {
      writeFile("dir/file.txt");
      createLink("dir", "link");

      await startWatcher();
      deleteFile("dir/file.txt");

      await inAnyOrder(
          [isRemoveEvent("dir/file.txt"), isRemoveEvent("link/file.txt")]);
    });

    test("symlink to a file", () async {
      writeFile("file.txt");
      createLink("file.txt", "link");

      await startWatcher();
      deleteLink("link");
      expectRemoveEvent("link");
    });

    test("symlink to a directory", () async {
      writeFile("dir/a.txt");
      writeFile("dir/b.txt");
      createLink("dir", "link");

      await startWatcher();
      deleteLink("link");

      await inAnyOrder(
          [isRemoveEvent("link/a.txt"), isRemoveEvent("link/b.txt")]);
    });
  });

  group("moving a", () {
    test("targeted file", () async {
      writeFile("old.txt");
      createLink("old.txt", "link");

      await startWatcher();
      renameFile("old.txt", "new.txt");

      await inAnyOrder([
        isRemoveEvent("old.txt"),
        isAddEvent("new.txt"),
        isRemoveEvent("link")
      ]);
    });

    test("targeted directory", () async {
      writeFile("old/file.txt");
      createLink("old", "link");

      await startWatcher();
      renameDir("old", "new");

      await inAnyOrder([
        isRemoveEvent("old/file.txt"),
        isAddEvent("new/file.txt"),
        isRemoveEvent("link/file.txt")
      ]);
    });

    test("subdirectory of a targeted directory", () async {
      writeFile("dir/old/file.txt");
      createLink("dir", "link");

      await startWatcher();
      renameDir("dir/old", "dir/new");

      await inAnyOrder([
        isRemoveEvent("dir/old/file.txt"),
        isAddEvent("dir/new/file.txt"),
        isRemoveEvent("link/old/file.txt"),
        isAddEvent("link/new/file.txt")
      ]);
    });

    test("moving a symlink to a file", () async {
      writeFile("file.txt");
      createLink("file.txt", "old");

      await startWatcher();
      renameLink("old", "new");

      await inAnyOrder([isRemoveEvent("old"), isAddEvent("new")]);
    });

    test("moving a symlink to a directory", () async {
      writeFile("dir/file.txt");
      createLink("dir", "old");

      await startWatcher();
      renameLink("old", "new");

      await inAnyOrder(
          [isRemoveEvent("old/file.txt"), isAddEvent("new/file.txt")]);
    });

    test("moving a symlink that was a file so that it's now a directory",
        () async {
      writeFile("entity/file.txt");
      writeFile("dir/entity");
      createLink("entity", "dir/link", relative: true);

      await startWatcher();
      renameLink("dir/link", "link");

      await inAnyOrder(
          [isRemoveEvent("dir/link"), isAddEvent("link/file.txt")]);
    });

    test("moving a symlink that was a directory so that it's now a file",
        () async {
      writeFile("entity/file.txt");
      writeFile("dir/entity");
      createLink("entity", "link", relative: true);

      await startWatcher();
      renameLink("link", "dir/link");

      await inAnyOrder(
          [isRemoveEvent("link/file.txt"), isAddEvent("dir/link")]);
    });
  });

  // We don't provide any guarantees about broken link behavior, but this
  // shouldn't break.
  test("creating a broken link", () async {
    await startWatcher();
    createLink("nonexistent", "broken");

    // Write a file and get an event to ensure that the watcher is actually
    // doing something.
    writeFile("file.txt");
    await inAnyOrder([isAddEvent("file.txt")]);
  });
}
