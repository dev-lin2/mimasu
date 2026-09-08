import '../../core/services/http/repo_index_fetcher.dart';
import '../../domain/entities/extension/extension_repo.dart';
import '../../domain/repositories/extension_repository.dart';
import '../../extensions/repo/repo_index_parser.dart';
import '../storage/repo_store.dart';

/// Turns what a user pasted into candidate index URLs.
///
/// People paste a repository's base URL as often as a direct index link, so
/// both are accepted. Where a base URL is given, `index.pb` is tried first:
/// section 6.1 records that at least one repository has migrated to protobuf
/// and left `index.min.json` as a stub, so preferring JSON would find two fake
/// entries and no catalogue.
abstract final class RepoUrlResolver {
  static const jsonIndexName = 'index.min.json';
  static const protobufIndexName = 'index.pb';

  /// A hostname, or `localhost`. Deliberately strict: `Uri.tryParse` accepts
  /// `https://not a url` and reports a host of "not a url", so parsing alone
  /// is not validation.
  static final _host = RegExp(
    r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?'
    r'(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$',
  );

  /// Returns the URLs to try in order, or an empty list if [entered] is not
  /// usable as a URL.
  static List<String> candidates(String entered) {
    final trimmed = entered.trim();
    if (trimmed.isEmpty) return const [];

    // Whitespace inside means this is prose, not an address.
    if (RegExp(r'\s').hasMatch(trimmed)) return const [];

    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return const [];
    if (!(uri.isScheme('http') || uri.isScheme('https'))) return const [];
    if (!_host.hasMatch(uri.host)) return const [];
    // A bare word is not a host worth trying.
    if (!uri.host.contains('.') && uri.host != 'localhost') return const [];

    final path = uri.path.toLowerCase();
    if (path.endsWith('.pb') || path.endsWith('.json')) {
      return [withScheme];
    }

    final base = withScheme.endsWith('/')
        ? withScheme.substring(0, withScheme.length - 1)
        : withScheme;
    return ['$base/$protobufIndexName', '$base/$jsonIndexName'];
  }
}

class ExtensionRepositoryImpl implements ExtensionRepository {
  ExtensionRepositoryImpl({
    required RepoIndexFetcher fetcher,
    required RepoStore store,
    RepoIndexParser parser = const RepoIndexParser(),
    DateTime Function() clock = DateTime.now,
  }) : _fetcher = fetcher,
       _store = store,
       _parser = parser,
       _clock = clock;

  final RepoIndexFetcher _fetcher;
  final RepoStore _store;
  final RepoIndexParser _parser;
  final DateTime Function() _clock;

  @override
  Future<List<ExtensionRepo>> savedRepos() async {
    final repos = await _store.load();
    return repos.toList()..sort((a, b) => b.fetchedAt.compareTo(a.fetchedAt));
  }

  @override
  Future<RepoCatalogue> addRepo(String enteredUrl) async {
    final catalogue = await _load(enteredUrl);

    final existing = await _store.load();
    final merged = [
      ...existing.where((r) => r.id != catalogue.repo.id),
      catalogue.repo,
    ];
    await _store.save(merged);
    return catalogue;
  }

  @override
  Future<RepoCatalogue> refreshRepo(ExtensionRepo repo) async {
    final catalogue = await _load(repo.enteredUrl);
    final existing = await _store.load();
    await _store.save([
      ...existing.where((r) => r.id != catalogue.repo.id && r.id != repo.id),
      catalogue.repo,
    ]);
    return catalogue;
  }

  @override
  Future<RepoCatalogue> catalogue(ExtensionRepo repo) => _load(repo.enteredUrl);

  @override
  Future<void> removeRepo(String id) async {
    final existing = await _store.load();
    await _store.save(existing.where((r) => r.id != id).toList());
  }

  /// The one path that fetches and parses. Every failure leaves here as a
  /// [RepoFailure] carrying a sentence fit for display.
  Future<RepoCatalogue> _load(String enteredUrl) async {
    final candidates = RepoUrlResolver.candidates(enteredUrl);
    if (candidates.isEmpty) {
      throw const RepoFailure(
        RepoFailureKind.invalidUrl,
        "That doesn't look like a URL. Paste the address of a repository "
            'index, or the folder containing one.',
      );
    }

    RepoFailure? lastFailure;
    for (final url in candidates) {
      final FetchResult result;
      try {
        result = await _fetcher.get(url);
      } on FetchUnreachable catch (e) {
        lastFailure = RepoFailure(
          RepoFailureKind.unreachable,
          'Could not reach $url. Check the address and your connection.',
        );
        _log(e);
        continue;
      }

      if (!result.isOk) {
        lastFailure = RepoFailure(
          RepoFailureKind.httpError,
          'The server answered ${result.statusCode} for $url.',
          statusCode: result.statusCode,
        );
        continue;
      }

      try {
        final index = _parser.parse(result.bytes, baseUrl: url);
        if (index.extensions.isEmpty) {
          lastFailure = const RepoFailure(
            RepoFailureKind.emptyIndex,
            'That index parsed but lists no extensions.',
          );
          continue;
        }
        return RepoCatalogue(
          repo: ExtensionRepo.fromIndex(
            url: url,
            enteredUrl: enteredUrl,
            index: index,
            fetchedAt: _clock(),
          ),
          index: index,
        );
      } on RepoIndexException catch (e) {
        lastFailure = RepoFailure(
          RepoFailureKind.unreadable,
          'Fetched $url, but it is not a repository index Mimasu can read.',
        );
        _log(e);
        continue;
      }
    }

    throw lastFailure ??
        const RepoFailure(
          RepoFailureKind.unreadable,
          'Could not read a repository index from that address.',
        );
  }

  // Kept deliberately trivial; wiring `logger` in belongs with the rest of
  // core/log, not here.
  void _log(Object error) {
    assert(() {
      // ignore: avoid_print
      print('[repo] $error');
      return true;
    }());
  }
}
