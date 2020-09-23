import '../watcher.dart';

/// Defines a way to create a custom watcher instead of the default ones.
///
/// This will be used when a [DirectoryWatcher] or [FileWatcher] would be
/// created and will take precedence over the default ones.
abstract class CustomWatcherFactory {
  /// Uniquely identify this watcher.
  String get id;

  /// Tries to create a [DirectoryWatcher] for the provided path.
  ///
  /// Should return `null` if the path is not supported by this factory.
  DirectoryWatcher createDirectoryWatcher(String path, {Duration pollingDelay});

  /// Tries to create a [FileWatcher] for the provided path.
  ///
  /// Should return `null` if the path is not supported by this factory.
  FileWatcher createFileWatcher(String path, {Duration pollingDelay});
}

/// Registers a custom watcher.
///
/// It's only allowed to register a watcher once per [id]. The [supportsPath]
/// will be called to determine if the [createWatcher] should be used instead of
/// the built-in watchers.
///
/// Note that we will try [CustomWatcherFactory] one by one in the order they
/// were registered.
void registerCustomWatcherFactory(CustomWatcherFactory customFactory) {
  if (_customWatcherFactories.containsKey(customFactory.id)) {
    throw ArgumentError('A custom watcher with id `${customFactory.id}` '
        'has already been registered');
  }
  _customWatcherFactories[customFactory.id] = customFactory;
}

/// Unregisters a custom watcher and returns it (returns `null` if it was never
/// registered).
CustomWatcherFactory unregisterCustomWatcherFactory(String id) =>
    _customWatcherFactories.remove(id);

Iterable<CustomWatcherFactory> get customWatcherFactories =>
    _customWatcherFactories.values;

final _customWatcherFactories = <String, CustomWatcherFactory>{};
