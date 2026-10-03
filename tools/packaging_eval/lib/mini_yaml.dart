// A YAML subset, enough for a pubspec and a pubspec.lock, and nothing more.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// The local package repository has to serve each package's pubspec as JSON in
// the version listing, and the consumer-gen assertion has to read a
// pubspec.lock. Both mean parsing YAML, and this package has no dependencies
// by design (AGENTS.md rule 9 asks for the list; the shortest list is empty),
// so this is a deliberately small parser with a hard rule: anything it does
// not understand raises, rather than being guessed at. It is not a YAML
// implementation and must not become one — if a pubspec here ever needs
// anchors or flow collections, take the dependency instead.
//
// Supported: block mappings nested by indentation, block sequences of scalars
// and of mappings, `#` comments, single- and double-quoted scalars, the plain
// scalars pubspecs use, and the `>-` / `>` / `|` / `|-` block scalars used for
// descriptions.

class MiniYamlException implements Exception {
  MiniYamlException(this.message, this.line);

  final String message;
  final int line;

  @override
  String toString() => 'MiniYamlException: $message (line $line)';
}

/// Parses [source] into `Map<String, Object?>` / `List<Object?>` / scalars.
Map<String, Object?> parseMiniYaml(String source) {
  final lines = _tokenize(source);
  final parser = _Parser(lines);
  final value = parser.parseBlock(0);
  if (value is Map<String, Object?>) return value;
  if (value == null) return <String, Object?>{};
  throw MiniYamlException('document is not a mapping', 1);
}

class _Line {
  _Line(this.number, this.indent, this.text);

  final int number;
  final int indent;
  final String text;
}

List<_Line> _tokenize(String source) {
  final result = <_Line>[];
  var number = 0;
  for (final raw in source.split('\n')) {
    number++;
    if (raw.trim().isEmpty) continue;
    final withoutComment = _stripComment(raw);
    if (withoutComment.trim().isEmpty) continue;
    if (withoutComment.trimLeft().startsWith('---') ||
        withoutComment.trimLeft().startsWith('...')) {
      throw MiniYamlException('multi-document YAML is not supported', number);
    }
    final indent = withoutComment.length - withoutComment.trimLeft().length;
    if (withoutComment.substring(0, indent).contains('\t')) {
      throw MiniYamlException('tab indentation is not supported', number);
    }
    result.add(_Line(number, indent, withoutComment.trimRight()));
  }
  return result;
}

/// Removes a `#` comment, respecting quotes.
String _stripComment(String line) {
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == "'" && !inDouble) inSingle = !inSingle;
    if (ch == '"' && !inSingle) inDouble = !inDouble;
    if (ch == '#' && !inSingle && !inDouble) {
      if (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t') {
        return line.substring(0, i);
      }
    }
  }
  return line;
}

class _Parser {
  _Parser(this.lines);

  final List<_Line> lines;
  int position = 0;

  _Line? get current => position < lines.length ? lines[position] : null;

  Object? parseBlock(int indent) {
    final line = current;
    if (line == null || line.indent < indent) return null;
    if (line.text.trimLeft().startsWith('- ') || line.text.trimLeft() == '-') {
      return _parseSequence(line.indent);
    }
    return _parseMapping(line.indent);
  }

  Map<String, Object?> _parseMapping(int indent) {
    final map = <String, Object?>{};
    while (true) {
      final line = current;
      if (line == null || line.indent < indent) break;
      if (line.indent > indent) {
        throw MiniYamlException('unexpected indentation', line.number);
      }
      final text = line.text.trimLeft();
      if (text.startsWith('- ')) break;

      final colon = _findKeyColon(text);
      if (colon < 0) {
        throw MiniYamlException('expected `key:`, got `$text`', line.number);
      }
      final key = _unquote(text.substring(0, colon).trim(), line.number);
      final rest = text.substring(colon + 1).trim();
      position++;

      if (rest.isEmpty) {
        // A block sequence may sit at the key's own indentation, which the
        // workspace root's `workspace:` list does not use but plenty of YAML
        // does.
        final next = current;
        if (next != null &&
            next.indent == indent &&
            (next.text.trimLeft().startsWith('- ') ||
                next.text.trimLeft() == '-')) {
          map[key] = _parseSequence(indent);
        } else {
          map[key] = parseBlock(indent + 1);
        }
      } else if (rest == '>-' || rest == '>' || rest == '|' || rest == '|-') {
        map[key] = _parseBlockScalar(indent + 1, folded: rest.startsWith('>'));
      } else {
        map[key] = _scalar(rest, line.number);
      }
    }
    return map;
  }

  List<Object?> _parseSequence(int indent) {
    final list = <Object?>[];
    while (true) {
      final line = current;
      if (line == null || line.indent < indent) break;
      final text = line.text.trimLeft();
      if (!text.startsWith('- ') && text != '-') break;
      if (line.indent > indent) {
        throw MiniYamlException('unexpected indentation', line.number);
      }
      final rest = text == '-' ? '' : text.substring(2).trim();
      position++;
      if (rest.isEmpty) {
        list.add(parseBlock(indent + 1));
        continue;
      }
      final colon = _findKeyColon(rest);
      if (colon >= 0) {
        // `- key: value` starts an inline mapping whose remaining keys are
        // indented to the position after the dash.
        final map = <String, Object?>{};
        final key = _unquote(rest.substring(0, colon).trim(), line.number);
        final value = rest.substring(colon + 1).trim();
        map[key] = value.isEmpty
            ? parseBlock(indent + 3)
            : _scalar(value, line.number);
        final nested = current;
        if (nested != null && nested.indent > indent) {
          final more = _parseMapping(nested.indent);
          map.addAll(more);
        }
        list.add(map);
        continue;
      }
      list.add(_scalar(rest, line.number));
    }
    return list;
  }

  String _parseBlockScalar(int indent, {required bool folded}) {
    final parts = <String>[];
    while (true) {
      final line = current;
      if (line == null || line.indent < indent) break;
      parts.add(line.text.trimLeft());
      position++;
    }
    return folded ? parts.join(' ') : parts.join('\n');
  }

  /// The index of the `:` that separates a key from its value, ignoring one
  /// inside quotes and the `:` of a `http://` style scalar.
  int _findKeyColon(String text) {
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == "'" && !inDouble) inSingle = !inSingle;
      if (ch == '"' && !inSingle) inDouble = !inDouble;
      if (ch != ':' || inSingle || inDouble) continue;
      final next = i + 1 < text.length ? text[i + 1] : ' ';
      if (next == ' ' || i == text.length - 1) return i;
    }
    return -1;
  }

  Object? _scalar(String raw, int number) {
    if (raw.startsWith('[') || raw.startsWith('{')) {
      throw MiniYamlException('flow collections are not supported', number);
    }
    if (raw.startsWith('&') || raw.startsWith('*')) {
      throw MiniYamlException('anchors and aliases are not supported', number);
    }
    final text = _unquote(raw, number);
    if (raw.startsWith('"') || raw.startsWith("'")) return text;
    if (text == 'null' || text == '~') return null;
    if (text == 'true') return true;
    if (text == 'false') return false;
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;
    return text;
  }

  String _unquote(String raw, int number) {
    if (raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'")) {
      return raw.substring(1, raw.length - 1).replaceAll("''", "'");
    }
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      return raw
          .substring(1, raw.length - 1)
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
    }
    if (raw.contains('"') && raw.startsWith('"')) {
      throw MiniYamlException('unterminated quoted scalar', number);
    }
    return raw;
  }
}
