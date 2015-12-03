// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Benchmarks for the PathSet class.
library watcher.benchmark.path_set;

import 'dart:io';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:path/path.dart' as p;

import 'package:watcher/src/path_set.dart';

final String root = Platform.isWindows ? r"C:\root" : "/root";

/// Base class for benchmarks on [PathSet].
abstract class PathSetBenchmark extends BenchmarkBase {
  PathSetBenchmark(String method) : super("PathSet.$method");

  final PathSet pathSet = new PathSet(root);

  /// Walks over a virtual directory [depth] levels deep invoking [callback]
  /// for each "file".
  ///
  /// Each virtual directory contains ten entries: either subdirectories or
  /// files.
  void walkTree(int depth, callback(String path)) {
    recurse(path, remainingDepth) {
      for (var i = 0; i < 10; i++) {
        var padded = i.toString().padLeft(2, '0');
        if (remainingDepth == 0) {
          callback(p.join(path, "file_$padded.txt"));
        } else {
          var subdir = p.join(path, "subdirectory_$padded");
          recurse(subdir, remainingDepth - 1);
        }
      }
    }

    recurse(root, depth);
  }
}

class AddBenchmark extends PathSetBenchmark {
  AddBenchmark() : super("add()");

  final List<String> paths = [];

  void setup() {
    // Make a bunch of paths in about the same order we expect to get them from
    // Directory.list().
    walkTree(3, paths.add);
  }

  void run() {
    for (var path in paths) pathSet.add(path);
  }
}

class ToSetBenchmark extends PathSetBenchmark {
  ToSetBenchmark() : super("toSet()");

  void setup() {
    walkTree(3, pathSet.add);
  }

  void run() {
    for (var _ in pathSet.toSet()) {
      // Do nothing.
    }
  }
}

main() {
  new AddBenchmark().report();
  new ToSetBenchmark().report();
}
