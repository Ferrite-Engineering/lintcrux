// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io' show File, RandomAccessFile;
import 'dart:typed_data';

import 'package:crux_netlist/crux_netlist.dart';

/// Reads the part of a Yosys `write_json` document the CDC analysis uses,
/// without holding the document, or a decoded copy of it, in memory.
///
/// A flattened SoC netlist is large: OpenTitan's earlgrey writes 864 MB.
/// Decoding that with `jsonDecode` first builds a generic map-and-list tree
/// several times the size of the text, and only then the [NetlistModel], so
/// the run ran out of memory long before the analysis started. This reader
/// walks the bytes once, a chunk at a time, and builds the model directly.
///
/// What it keeps, which is what the analysis and its resolvers and
/// classifiers read:
///
/// * one module: the one named `topModule`, or with no name the first module
///   whose `top` attribute is set (the module `NetlistModel.topModule`
///   returns). Every other module is skipped unread. With a name that is not
///   in the document, the model has no module, as `modules[topModule]` would
///   be `null` in a fully decoded one;
/// * that module's attributes, its ports (direction and bits) and its net
///   names (bits and `hide_name`);
/// * each cell's type, `hide_name`, connections and `src` attribute.
///
/// What it drops: cell parameters and port directions, every other cell
/// attribute, and net attributes. An attribute value that is an object or a
/// list reads as an empty string. Everything kept has exactly the value
/// [YosysJsonParser] would give it.
///
/// Malformed or truncated input throws [FormatException].
class CdcNetlistReader {
  /// Creates a reader. No state; instances are interchangeable.
  const CdcNetlistReader();

  /// Reads the netlist in [file].
  NetlistModel readFile(File file, {String? topModule}) {
    final handle = file.openSync();
    try {
      return _NetlistBuilder(
        _JsonPullReader(_FileChunks(handle)),
        topModule,
      ).read();
    } finally {
      handle.closeSync();
    }
  }

  /// Reads the netlist in [json], a document already in memory.
  ///
  /// Used when Yosys's output reached the engine as a string; the string is
  /// encoded a slice at a time, so no second full-size copy is made.
  NetlistModel readString(String json, {String? topModule}) =>
      _NetlistBuilder(_JsonPullReader(_StringChunks(json)), topModule).read();
}

/// Builds the [NetlistModel] from the token stream.
class _NetlistBuilder {
  _NetlistBuilder(this._json, this._topModule);

  final _JsonPullReader _json;
  final String? _topModule;

  /// One [NetBit] per net id, shared by every reference to that id.
  final List<NetBit?> _netBits = <NetBit?>[];

  /// Canonical copies of the short strings that repeat on every cell: cell
  /// types and connection port names.
  final Map<String, String> _interned = <String, String>{};

  NetlistModel read() {
    var creator = '';
    final modules = <String, Module>{};
    _json.readObject((key) {
      switch (key) {
        case 'creator':
          creator = _json.readScalarAsString();
        case 'modules':
          _json.readObject((name) {
            final module = _readModule(name, keepTop: modules.isEmpty);
            if (module != null) modules[name] = module;
          });
        default:
          _json.skipValue();
      }
    });
    _json.expectEnd();
    return NetlistModel(creator: creator, modules: modules);
  }

  /// Reads one module, returning it when it is the one to keep.
  ///
  /// [keepTop] is false once a top-marked module has been kept: with no
  /// name to look for, the first one wins.
  Module? _readModule(String name, {required bool keepTop}) {
    final named = _topModule;
    if (named != null && name != named) {
      _json.skipValue();
      return null;
    }
    if (named == null && !keepTop) {
      _json.skipValue();
      return null;
    }
    // Known to be wanted when it is the named module; otherwise decided by
    // its `top` attribute, which Yosys writes first.
    var wanted = named != null ? true : null;
    var attributes = <String, String>{};
    final ports = <String, Port>{};
    final cells = <String, Cell>{};
    final nets = <String, Net>{};
    _json.readObject((key) {
      if (wanted == false) {
        _json.skipValue();
        return;
      }
      try {
        switch (key) {
          case 'attributes':
            attributes = _readAttributes();
            wanted ??= _isSet(attributes['top']);
          case 'ports':
            _json.readObject((port) => ports[port] = _readPort(port));
          case 'cells':
            _json.readObject((cell) => cells[cell] = _readCell(cell));
          case 'netnames':
            _json.readObject((net) => nets[net] = _readNet(net));
          default:
            _json.skipValue();
        }
      } on FormatException catch (e) {
        throw FormatException('module "$name": ${e.message}');
      }
    });
    if (wanted == false) return null;
    if (wanted == null && !_isSet(attributes['top'])) return null;
    return Module(
      name: name,
      attributes: attributes,
      ports: ports,
      cells: cells,
      nets: nets,
    );
  }

  Port _readPort(String name) {
    String? direction;
    var bits = const <BitRef>[];
    _json.readObject((key) {
      switch (key) {
        case 'direction':
          direction = _json.readString();
        case 'bits':
          bits = _readBits();
        default:
          _json.skipValue();
      }
    });
    final dir = direction;
    if (dir == null) {
      throw FormatException('port "$name": `direction` is missing');
    }
    return Port(name: name, direction: PortDirection.fromJson(dir), bits: bits);
  }

  Cell _readCell(String name) {
    String? type;
    var hideName = false;
    var attributes = const <String, String>{};
    var connections = const <String, List<BitRef>>{};
    _json.readObject((key) {
      switch (key) {
        case 'type':
          type = _intern(_json.readString());
        case 'hide_name':
          hideName = _readHideName();
        case 'attributes':
          attributes = _readSrcOnly();
        case 'connections':
          final read = <String, List<BitRef>>{};
          _json.readObject((port) => read[_intern(port)] = _readBits());
          connections = read;
        default:
          _json.skipValue();
      }
    });
    final cellType = type;
    if (cellType == null) {
      throw FormatException('cell "$name": `type` is missing');
    }
    return Cell(
      name: name,
      type: cellType,
      parameters: const <String, String>{},
      attributes: attributes,
      portDirections: const <String, PortDirection>{},
      connections: connections,
      hideName: hideName,
    );
  }

  Net _readNet(String name) {
    var hideName = false;
    var bits = const <BitRef>[];
    _json.readObject((key) {
      switch (key) {
        case 'hide_name':
          hideName = _readHideName();
        case 'bits':
          bits = _readBits();
        default:
          _json.skipValue();
      }
    });
    return Net(
      name: name,
      bits: bits,
      attributes: const <String, String>{},
      hideName: hideName,
    );
  }

  Map<String, String> _readAttributes() {
    final out = <String, String>{};
    _json.readObject((key) => out[key] = _json.readScalarAsString());
    return out;
  }

  /// A cell's attributes, keeping `src` only: the one the analysis reads, and
  /// on a flattened design the others (`hdlname`, `module_not_derived`, …)
  /// are most of the bytes.
  Map<String, String> _readSrcOnly() {
    String? src;
    _json.readObject((key) {
      if (key == 'src') {
        src = _json.readScalarAsString();
      } else {
        _json.skipValue();
      }
    });
    final value = src;
    return value == null
        ? const <String, String>{}
        : <String, String>{'src': value};
  }

  bool _readHideName() {
    final value = _json.readScalar();
    if (value == null) return false;
    if (value is int) return value != 0;
    throw const FormatException('`hide_name` is not an integer');
  }

  List<BitRef> _readBits() {
    final bits = <BitRef>[];
    _json.readArray(() {
      final value = _json.readScalar();
      if (value is int && value >= 0) {
        bits.add(_netBit(value));
      } else {
        final bit = BitRef.fromJson(value);
        bits.add(bit is NetBit && bit.netId >= 0 ? _netBit(bit.netId) : bit);
      }
    });
    return bits;
  }

  NetBit _netBit(int id) {
    if (id >= _netBits.length) {
      _netBits.length = id + 1 > _netBits.length * 2
          ? id + 1
          : _netBits.length * 2;
    }
    return _netBits[id] ??= NetBit(id);
  }

  String _intern(String value) => _interned.putIfAbsent(value, () => value);

  /// The `top` / `blackbox` attribute test `Module.isTop` applies.
  static bool _isSet(String? raw) {
    if (raw == null || raw.isEmpty) return false;
    for (final code in raw.codeUnits) {
      if (code != 0x30) return true;
    }
    return false;
  }
}

/// A source of document bytes, one chunk at a time.
abstract class _Chunks {
  /// The next chunk, or `null` at the end of the document. A returned chunk
  /// is valid until the next call.
  Uint8List? next();
}

class _FileChunks implements _Chunks {
  _FileChunks(this._file);

  static const int _size = 1 << 20;

  final RandomAccessFile _file;
  final Uint8List _buffer = Uint8List(_size);

  @override
  Uint8List? next() {
    final n = _file.readIntoSync(_buffer);
    if (n <= 0) return null;
    return Uint8List.sublistView(_buffer, 0, n);
  }
}

class _StringChunks implements _Chunks {
  _StringChunks(this._source);

  static const int _size = 1 << 18;

  final String _source;
  int _offset = 0;

  @override
  Uint8List? next() {
    if (_offset >= _source.length) return null;
    var end = _offset + _size;
    if (end >= _source.length) {
      end = _source.length;
    } else if (_isHighSurrogate(_source.codeUnitAt(end - 1))) {
      // Never split a surrogate pair across two slices: each half would
      // encode as a replacement character.
      end--;
    }
    final slice = _source.substring(_offset, end);
    _offset = end;
    return utf8.encode(slice);
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}

/// A pull reader over JSON bytes: the caller says what it expects next and
/// the reader consumes exactly that, so nothing is decoded that is not used.
class _JsonPullReader {
  _JsonPullReader(this._chunks);

  final _Chunks _chunks;
  Uint8List _buffer = Uint8List(0);
  int _pos = 0;
  bool _done = false;

  /// Scratch space for string bytes.
  Uint8List _scratch = Uint8List(256);

  static const int _quote = 0x22;
  static const int _backslash = 0x5C;
  static const int _comma = 0x2C;
  static const int _colon = 0x3A;
  static const int _openBrace = 0x7B;
  static const int _closeBrace = 0x7D;
  static const int _openBracket = 0x5B;
  static const int _closeBracket = 0x5D;

  /// The next byte without consuming it, or -1 at the end.
  int _peekRaw() {
    if (_pos < _buffer.length) return _buffer[_pos];
    if (_done) return -1;
    final next = _chunks.next();
    if (next == null) {
      _done = true;
      _buffer = Uint8List(0);
      _pos = 0;
      return -1;
    }
    _buffer = next;
    _pos = 0;
    return _peekRaw();
  }

  /// The next byte that is not whitespace, not consumed, or -1 at the end.
  int _peek() {
    for (;;) {
      final c = _peekRaw();
      if (c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09) {
        _pos++;
        continue;
      }
      return c;
    }
  }

  int _take() {
    final c = _peekRaw();
    if (c < 0) throw const FormatException('Unexpected end of JSON input');
    _pos++;
    return c;
  }

  void _expect(int expected) {
    final c = _peek();
    if (c != expected) {
      throw FormatException(
        'Expected "${String.fromCharCode(expected)}" but found '
        '${_describe(c)} in JSON input',
      );
    }
    _pos++;
  }

  static String _describe(int c) =>
      c < 0 ? 'the end' : '"${String.fromCharCode(c)}"';

  /// Fails unless only whitespace is left.
  void expectEnd() {
    final c = _peek();
    if (c >= 0) {
      throw FormatException('Unexpected ${_describe(c)} after the JSON value');
    }
  }

  /// Reads an object, calling [onEntry] with each key; [onEntry] must
  /// consume the value.
  void readObject(void Function(String key) onEntry) {
    _expect(_openBrace);
    if (_peek() == _closeBrace) {
      _pos++;
      return;
    }
    for (;;) {
      final key = readString();
      _expect(_colon);
      onEntry(key);
      final c = _peek();
      if (c == _comma) {
        _pos++;
        continue;
      }
      if (c == _closeBrace) {
        _pos++;
        return;
      }
      throw FormatException('Expected "," or "}" but found ${_describe(c)}');
    }
  }

  /// Reads an array, calling [onElement] once per element; [onElement]
  /// must consume it.
  void readArray(void Function() onElement) {
    _expect(_openBracket);
    if (_peek() == _closeBracket) {
      _pos++;
      return;
    }
    for (;;) {
      onElement();
      final c = _peek();
      if (c == _comma) {
        _pos++;
        continue;
      }
      if (c == _closeBracket) {
        _pos++;
        return;
      }
      throw FormatException('Expected "," or "]" but found ${_describe(c)}');
    }
  }

  /// Reads a string value.
  String readString() {
    _expect(_quote);
    var length = 0;
    var ascii = true;
    for (;;) {
      final c = _take();
      if (c == _quote) break;
      if (c < 0x20) {
        throw const FormatException('Control character in JSON string');
      }
      if (c == _backslash) {
        final code = _readEscape();
        if (code < 0x80) {
          length = _put(length, code);
        } else {
          ascii = false;
          for (final b in utf8.encode(String.fromCharCode(code))) {
            length = _put(length, b);
          }
        }
        continue;
      }
      if (c >= 0x80) ascii = false;
      length = _put(length, c);
    }
    final bytes = Uint8List.sublistView(_scratch, 0, length);
    return ascii ? String.fromCharCodes(bytes) : utf8.decode(bytes);
  }

  int _put(int length, int byte) {
    if (length == _scratch.length) {
      _scratch = Uint8List(_scratch.length * 2)..setAll(0, _scratch);
    }
    _scratch[length] = byte;
    return length + 1;
  }

  /// The code point of the escape after a backslash, a surrogate pair
  /// joined into one.
  int _readEscape() {
    final c = _take();
    switch (c) {
      case _quote:
      case _backslash:
      case 0x2F: // '/'
        return c;
      case 0x62: // 'b'
        return 0x08;
      case 0x66: // 'f'
        return 0x0C;
      case 0x6E: // 'n'
        return 0x0A;
      case 0x72: // 'r'
        return 0x0D;
      case 0x74: // 't'
        return 0x09;
      case 0x75: // 'u'
        final unit = _readHex4();
        if (unit >= 0xD800 && unit <= 0xDBFF && _peekRaw() == _backslash) {
          _pos++;
          if (_take() != 0x75) {
            throw const FormatException('Invalid surrogate escape in JSON');
          }
          final low = _readHex4();
          if (low >= 0xDC00 && low <= 0xDFFF) {
            return 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
          }
          throw const FormatException('Invalid surrogate pair in JSON');
        }
        return unit;
      default:
        throw FormatException('Invalid escape ${_describe(c)} in JSON string');
    }
  }

  int _readHex4() {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final c = _take();
      final int digit;
      if (c >= 0x30 && c <= 0x39) {
        digit = c - 0x30;
      } else if (c >= 0x61 && c <= 0x66) {
        digit = c - 0x61 + 10;
      } else if (c >= 0x41 && c <= 0x46) {
        digit = c - 0x41 + 10;
      } else {
        throw const FormatException(r'Invalid \u escape in JSON string');
      }
      value = value * 16 + digit;
    }
    return value;
  }

  /// Reads a string, number, `true`, `false` or `null`, as `jsonDecode`
  /// would give it.
  Object? readScalar() {
    final c = _peek();
    if (c == _quote) return readString();
    if (c == 0x2D || (c >= 0x30 && c <= 0x39)) return _readNumber();
    if (c == 0x74) return _readLiteral('true', true);
    if (c == 0x66) return _readLiteral('false', false);
    if (c == 0x6E) return _readLiteral('null', null);
    throw FormatException('Expected a JSON value but found ${_describe(c)}');
  }

  /// A scalar the way the netlist model stores an attribute value:
  /// `value?.toString() ?? ''`. An object or a list is skipped and reads as
  /// an empty string.
  String readScalarAsString() {
    final c = _peek();
    if (c == _openBrace || c == _openBracket) {
      skipValue();
      return '';
    }
    return readScalar()?.toString() ?? '';
  }

  Object? _readLiteral(String word, Object? value) {
    for (var i = 0; i < word.length; i++) {
      if (_take() != word.codeUnitAt(i)) {
        throw FormatException('Invalid literal in JSON, expected "$word"');
      }
    }
    return value;
  }

  num _readNumber() {
    // The number's text goes to the string scratch space, which is free
    // between strings, and is only turned into a String for the rare number
    // that is not a short integer.
    var length = 0;
    var integral = true;
    var value = 0;
    var negative = false;
    var count = 0;
    for (;;) {
      final c = _peekRaw();
      if (c >= 0x30 && c <= 0x39) {
        if (integral && count < 18) value = value * 10 + (c - 0x30);
        count++;
      } else if (c == 0x2D && length == 0) {
        negative = true;
      } else if (c == 0x2E ||
          c == 0x65 ||
          c == 0x45 ||
          c == 0x2B ||
          c == 0x2D) {
        // A fraction or an exponent (whose sign may be `-`): not an int.
        integral = false;
      } else {
        break;
      }
      length = _put(length, c);
      _pos++;
    }
    if (count == 0) throw const FormatException('Invalid number in JSON');
    if (integral && count < 18) return negative ? -value : value;
    final text = String.fromCharCodes(
      Uint8List.sublistView(_scratch, 0, length),
    );
    return num.tryParse(text) ??
        (throw FormatException('Invalid number "$text" in JSON'));
  }

  /// Consumes one value of any kind without building it.
  void skipValue() {
    final c = _peek();
    if (c == _openBrace || c == _openBracket) {
      _skipContainer();
    } else if (c == _quote) {
      _skipString();
    } else {
      readScalar();
    }
  }

  void _skipString() {
    _expect(_quote);
    for (;;) {
      final c = _take();
      if (c == _quote) return;
      if (c == _backslash) _take();
    }
  }

  /// Skips a balanced object or array. Brackets inside strings do not count.
  void _skipContainer() {
    var depth = 0;
    for (;;) {
      final c = _peekRaw();
      if (c < 0) throw const FormatException('Unexpected end of JSON input');
      if (c == _quote) {
        _skipString();
        continue;
      }
      _pos++;
      if (c == _openBrace || c == _openBracket) {
        depth++;
      } else if (c == _closeBrace || c == _closeBracket) {
        depth--;
        if (depth == 0) return;
      }
    }
  }
}
