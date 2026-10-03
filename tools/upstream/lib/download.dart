import 'dart:io';

final _repoPattern = RegExp(r'^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$');

/// The immutable source-archive URL for `<repo>` at `<tag>`.
///
/// `codeload.github.com` serves the same bytes the "Source code (tar.gz)"
/// release link serves, without a redirect. The URL is a pure function of the
/// two manifest fields, which is what lets CI fetch exactly the pin.
///
/// This is the only network destination the tool ever contacts, and it is
/// contacted only in build-time tooling — never from the three published
/// packages (repo rule 3).
String sourceArchiveUrl({required String repo, required String tag}) {
  if (!_repoPattern.hasMatch(repo)) {
    throw ArgumentError.value(repo, 'repo', 'Expected "<owner>/<name>"');
  }
  if (tag.isEmpty) {
    throw ArgumentError.value(tag, 'tag', 'Tag must not be empty');
  }
  if (tag.contains('/') || tag.contains('..') || tag.contains('%')) {
    throw ArgumentError.value(
      tag,
      'tag',
      'Tag must not contain "/", ".." or "%"',
    );
  }
  return 'https://codeload.github.com/$repo/tar.gz/refs/tags/$tag';
}

/// Downloads the source archive for [repo] at [tag] to [destination].
///
/// Used by CI only. It is unreachable from the development sandbox, so the
/// tested path is `--from <path>`; what is unit-tested here is
/// [sourceArchiveUrl], the part that decides *which* bytes CI fetches.
Future<void> downloadSourceArchive({
  required String repo,
  required String tag,
  required File destination,
}) async {
  final url = sourceArchiveUrl(repo: repo, tag: tag);
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.followRedirects = true;
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'GET $url returned ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    destination.parent.createSync(recursive: true);
    await response.pipe(destination.openWrite());
  } finally {
    client.close(force: true);
  }
}
