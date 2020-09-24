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
  /// Returns `null` if the path is not supported by this factory.
  DirectoryWatcher createDirectoryWatcher(String path, {Duration pollingDelay});

  /// Tries to create a [FileWatcher] for the provided path.
  ///
  /// Returns `null` if the path is not supported by this factory.
  FileWatcher createFileWatcher(String path, {Duration pollingDelay});
}

/// Registers a custom watcher.
///
/// It's only allowed to register a watcher factory once per [id] and at most
/// one factory should apply to any given file (creating a [Watcher] will fail
/// otherwise).
void registerCustomWatcherFactory(CustomWatcherFactory customFactory) {
  if (_customWatcherFactories.containsKey(customFactory.id)) {
    throw ArgumentError('A custom watcher with id `${customFactory.id}` '
        'has already been registered');
  }
  _customWatcherFactories[customFactory.id] = customFactory;
}

/// Tries to create a custom [DirectoryWatcher] and returns it.
///
/// Returns `null` if no custom watcher was applicable and throws a [StateError]
/// if more than one was.
DirectoryWatcher createCustomDirectoryWatcher(String path,
    {Duration pollingDelay}) {
  DirectoryWatcher customWatcher;
  String customFactoryId;
  for (var watcherFactory in customWatcherFactories) {
    if (customWatcher != null) {
      throw StateError('Two `CustomWatcherFactory`s applicable: '
          '`$customFactoryId` and `${watcherFactory.id}` for `$path`');
    }
    customWatcher =
        watcherFactory.createDirectoryWatcher(path, pollingDelay: pollingDelay);
    customFactoryId = watcherFactory.id;
  }
  return customWatcher;
}

/// Tries to create a custom [FileWatcher] and returns it.
///
/// Returns `null` if no custom watcher was applicable and throws a [StateError]
/// if more than one was.
FileWatcher createCustomFileWatcher(String path, {Duration pollingDelay}) {
  FileWatcher customWatcher;
  String customFactoryId;
  for (var watcherFactory in customWatcherFactories) {
    if (customWatcher != null) {
      throw StateError('Two `CustomWatcherFactory`s applicable: '
          '`$customFactoryId` and `${watcherFactory.id}` for `$path`');
    }
    customWatcher =
        watcherFactory.createFileWatcher(path, pollingDelay: pollingDelay);
    customFactoryId = watcherFactory.id;
  }
  return customWatcher;
}

/// Unregisters a custom watcher and returns it.
///
/// Returns `null` if the id was never registered.
CustomWatcherFactory unregisterCustomWatcherFactory(String id) =>
    _customWatcherFactories.remove(id);

Iterable<CustomWatcherFactory> get customWatcherFactories =>
    _customWatcherFactories.values;

final _customWatcherFactories = <String, CustomWatcherFactory>{};
