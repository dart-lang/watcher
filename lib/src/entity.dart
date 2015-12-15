// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library watcher.entity;

import 'dart:io';

/// Metadata about a filesystem entity.
class Entity {
  /// The entity's path.
  final String path;

  /// The type of the entity.
  ///
  /// This will never be [FileSystemEntityType.LINK]. If it's
  /// [FileSystemEntityType.NOT_FOUND], that indicates that the entity has been
  /// removed.
  final FileSystemEntityType type;

  /// Whether the entity is a symlink.
  final bool isLink;

  /// Whether the entity is a file.
  bool get isFile => type == FileSystemEntityType.FILE;

  /// Whether the entity is a directory.
  bool get isDirectory => type == FileSystemEntityType.DIRECTORY;

  /// Whether this entity has been removed.
  bool get isRemoved => type == FileSystemEntityType.NOT_FOUND;

  Entity(this.path, this.type, {this.isLink: false});

  /// Constructs an [Entity] representing a removed entity.
  Entity.removed(String path) : this(path, FileSystemEntityType.NOT_FOUND);

  String toString() {
    var buffer = new StringBuffer();
    if (isLink) buffer.write('symlinked ');
    if (isRemoved) buffer.write('removed ');
    if (isFile) buffer.write('file ');
    if (isDirectory) buffer.write('directory ');
    buffer.write(path);
    return buffer.toString();
  }
}
