import '../entities/extension/extension_repo.dart';
import '../entities/extension/extension_repo_index.dart';

/// A repository plus the catalogue read from it.
class RepoCatalogue {
  const RepoCatalogue({required this.repo, required this.index});
  final ExtensionRepo repo;
  final ExtensionRepoIndex index;
}

/// Why adding or refreshing a repository failed. Typed so the UI can say
/// something specific instead of dumping an exception (INSTRUCTIONS.md 5.8).
enum RepoFailureKind {
  /// The text the user pasted is not a usable URL.
  invalidUrl,

  /// Nothing answered, or the request timed out.
  unreachable,

  /// The server answered, but not with 200.
  httpError,

  /// Fetched, but not a repository index in any format Mimasu reads.
  unreadable,

  /// Reached and parsed, but the repository lists no extensions at all.
  emptyIndex,
}

class RepoFailure implements Exception {
  const RepoFailure(this.kind, this.message, {this.statusCode});
  final RepoFailureKind kind;

  /// User-facing, already phrased for display.
  final String message;
  final int? statusCode;

  @override
  String toString() => 'RepoFailure($kind): $message';
}

/// Managing extension repositories. Implemented in `data/`, consumed by
/// cubits, which must never see a Dio, Hive or channel type (section 3).
abstract interface class ExtensionRepository {
  /// Repositories the user has added, most recently fetched first.
  Future<List<ExtensionRepo>> savedRepos();

  /// Resolves [enteredUrl] to an index, fetches, parses and persists it.
  ///
  /// Throws [RepoFailure] and nothing else.
  Future<RepoCatalogue> addRepo(String enteredUrl);

  /// Re-fetches a repository already saved.
  Future<RepoCatalogue> refreshRepo(ExtensionRepo repo);

  /// Reads a saved repository's catalogue. Always goes to the network for now;
  /// index caching arrives with the rest of Phase 1.
  Future<RepoCatalogue> catalogue(ExtensionRepo repo);

  Future<void> removeRepo(String id);
}
