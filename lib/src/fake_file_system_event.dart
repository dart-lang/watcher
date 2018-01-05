// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// An implementation of [FileSystemEvent] with an accessible constructor.
///
/// This is used to work around sdk#24815. The events emitted by `dart:io` have
/// the wrong path, so we wrap them with our own events with fixed paths.
abstract class FakeFileSystemEvent implements FileSystemEvent {
  final String path;
  final bool isDirectory;

  FakeFileSystemEvent._(this.path, {this.isDirectory: false});

  /// Returns a copy of [event] with any paths that were relative to [oldRoot]
  /// relative to [newRoot] instead.
  factory FakeFileSystemEvent.rebase(
      FileSystemEvent event, String oldRoot, String newRoot) {
    var relativePath = p.relative(event.path, from: oldRoot);
    var fixedPath = p.join(newRoot, relativePath);

    if (event is FileSystemMoveEvent) {
      var relativeDestination = p.relative(event.destination, from: oldRoot);
      var fixedDestination = p.join(newRoot, relativeDestination);

      return new FakeFileSystemMoveEvent(fixedPath, fixedDestination,
          isDirectory: event.isDirectory);
    } else {
      return new FakeFileSystemEvent.withPath(event, fixedPath);
    }
  }

  /// Returns a copy of [event] with [event.path] changed to [path].
  factory FakeFileSystemEvent.withPath(FileSystemEvent event, String path) {
    if (event is FileSystemCreateEvent) {
      return new FakeFileSystemCreateEvent(path,
          isDirectory: event.isDirectory);
    } else if (event is FileSystemDeleteEvent) {
      return new FakeFileSystemDeleteEvent(path,
          isDirectory: event.isDirectory);
    } else if (event is FileSystemModifyEvent) {
      return new FakeFileSystemModifyEvent(path,
          isDirectory: event.isDirectory, contentChanged: event.contentChanged);
    } else if (event is FileSystemMoveEvent) {
      return new FakeFileSystemMoveEvent(path, event.destination,
          isDirectory: event.isDirectory);
    }
  }
}

class FakeFileSystemCreateEvent extends FakeFileSystemEvent
    implements FileSystemCreateEvent {
  final type = FileSystemEvent.CREATE;

  FakeFileSystemCreateEvent(String path, {bool isDirectory: false})
      : super._(path, isDirectory: isDirectory);

  String toString() {
    var str = 'FakeFileSystemCreateEvent("$path"';
    if (isDirectory) str += ', isDirectory: true';
    return str + ")";
  }
}

class FakeFileSystemDeleteEvent extends FakeFileSystemEvent
    implements FileSystemDeleteEvent {
  final type = FileSystemEvent.DELETE;

  FakeFileSystemDeleteEvent(String path, {bool isDirectory: false})
      : super._(path, isDirectory: isDirectory);

  String toString() {
    var str = 'FakeFileSystemDeleteEvent("$path"';
    if (isDirectory) str += ', isDirectory: true';
    return str + ")";
  }
}

class FakeFileSystemModifyEvent extends FakeFileSystemEvent
    implements FileSystemModifyEvent {
  final type = FileSystemEvent.MODIFY;
  final bool contentChanged;

  FakeFileSystemModifyEvent(String path,
      {bool isDirectory: false, this.contentChanged: false})
      : super._(path, isDirectory: isDirectory);

  String toString() {
    var str = 'FakeFileSystemModifyEvent("$path"';
    if (isDirectory) str += ', isDirectory: true';
    if (contentChanged) str += ', contentChanged: true';
    return str + ")";
  }
}

class FakeFileSystemMoveEvent extends FakeFileSystemEvent
    implements FileSystemMoveEvent {
  final type = FileSystemEvent.MOVE;
  final String destination;

  FakeFileSystemMoveEvent(String path, this.destination,
      {bool isDirectory: false})
      : super._(path, isDirectory: isDirectory);

  String toString() {
    var str = 'FakeFileSystemMoveEvent("$path", "$destination"';
    if (isDirectory) str += ', isDirectory: true';
    return str + ")";
  }
}
