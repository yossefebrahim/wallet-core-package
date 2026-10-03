/// The fetcher's hashing, run once against a real multi-megabyte file rather
/// than against fixtures it produced itself.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// The file is upstream's own 4.8.0 source archive, which
/// `tools/native_build/build_apple.sh` caches under `$WCF_UPSTREAM_CACHE`. It
/// is not ours and this test does not fetch it: if it is not on this machine
/// the test skips, so a clean checkout is not blocked on a 40 MB download. Its
/// digest is upstream's `SHA256SUMS` entry for
/// `TrustWalletCore-4.8.0.tar.xz`, and it exists here to show that the chunked
/// hashing the fetcher verifies with agrees with an externally produced digest
/// on a file large enough to cross many chunk boundaries.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/asset_names.dart';
import '../../tool/src/fetcher.dart';

const String _expectedDigest =
    '30b0532d9f143b6409aa405f3ba124625fb01e70f13d8e52b3904334c617ff60';

void main() {
  final home = Platform.environment['HOME'];
  final cacheRoot =
      Platform.environment['WCF_UPSTREAM_CACHE'] ??
      (home == null ? null : '$home/.cache/wcf-upstream');
  final archive = cacheRoot == null
      ? null
      : File('$cacheRoot/4.8.0/TrustWalletCore-4.8.0.tar.xz');
  final present = archive != null && archive.existsSync();

  test(
    'chunked hashing of a real upstream archive matches its published digest',
    () async {
      final result = await sha256OfFile(archive!);
      expect(result.digest, _expectedDigest);
      expect(isSha256(result.digest), isTrue);
      expect(result.size, archive.lengthSync());
      expect(result.size, greaterThan(1 << 20));
    },
    skip: present
        ? false
        : 'no cached upstream archive at '
              '${archive?.path ?? "<no HOME and no WCF_UPSTREAM_CACHE>"}; '
              'run `melos run native:host-lib` or fetch it by hand to enable '
              'this test',
  );

  test('a truncated copy of the same file hashes differently', () async {
    final tmp = Platform.environment['TMPDIR'] ?? Directory.systemTemp.path;
    final dir = Directory(tmp).createTempSync('wcf-hash-test-');
    addTearDown(() => dir.deleteSync(recursive: true));

    final file = File('${dir.path}/blob')
      ..writeAsBytesSync(List<int>.generate(200000, (i) => i % 256));
    final full = await sha256OfFile(file);

    file.writeAsBytesSync(List<int>.generate(199999, (i) => i % 256));
    final short = await sha256OfFile(file);

    expect(full.size, 200000);
    expect(short.size, 199999);
    expect(short.digest, isNot(full.digest));
  });
}
