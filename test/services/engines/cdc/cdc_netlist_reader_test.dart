// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_netlist/crux_netlist.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';
import 'package:lintcrux/services/engines/cdc/cdc_netlist_reader.dart';
import 'package:path/path.dart' as p;

// The CDC netlist reader streams Yosys's `write_json` document and keeps only
// what the analysis reads, so a flattened SoC (OpenTitan earlgrey: 864 MB of
// JSON) is never held, or decoded, whole (lintcrux#31).
//
// The reference for every expectation here is `YosysJsonParser`, the full
// decoder the engine used before: whatever the reader keeps must be exactly
// what the parser gives for it.

/// A hand-written document in the shape `write_json` writes, with the parts
/// the reader skips (other modules, parameters, port directions, extra
/// attributes, a `memories` section) and the awkward JSON a real one can
/// carry: escapes, a non-ASCII path, constant and numeric-string bits,
/// numbers with fractions and exponents, nested attribute values.
Map<String, Object?> _document() => <String, Object?>{
  'creator': 'Yosys 0.70 (hand-written)',
  'modules': <String, Object?>{
    'leaf': <String, Object?>{
      'attributes': <String, Object?>{'blackbox': '00000001'},
      'ports': <String, Object?>{
        'a': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2],
        },
      },
      'cells': <String, Object?>{},
      'netnames': <String, Object?>{},
    },
    'top': <String, Object?>{
      'attributes': <String, Object?>{
        'top': '00000000000000000000000000000001',
        'src': 'rtl/töp.sv:1.1-40.10',
        'dynports': 1,
      },
      'parameter_default_values': <String, Object?>{
        'W': '00000000000000000000000000001000',
      },
      'ports': <String, Object?>{
        'clk_a': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2],
        },
        'clk_b': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[3],
        },
        'd': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[4, '5', '0', 'x'],
          'offset': 1,
          'upto': 1,
        },
        'q': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[8, 9],
        },
      },
      'cells': <String, Object?>{
        r'$procdff$12': <String, Object?>{
          'hide_name': 1,
          'type': r'$adff',
          'parameters': <String, Object?>{
            'WIDTH': '00000000000000000000000000000010',
            'ARST_VALUE': 0,
          },
          'attributes': <String, Object?>{
            'src': r'rtl/töp.sv:23.3-23.20|rtl/"quoted"\x.sv:1.1',
            'hdlname': r'u_sync \stage',
            'module_not_derived': 1,
            'nested': <String, Object?>{
              'k': <Object?>[1, 2.5e-3, true, null],
            },
          },
          'port_directions': <String, Object?>{
            'CLK': 'input',
            'ARST': 'input',
            'D': 'input',
            'Q': 'output',
          },
          'connections': <String, Object?>{
            'CLK': <Object>[2],
            'ARST': <Object>['1'],
            'D': <Object>[4, 5],
            'Q': <Object>[6, 7],
          },
        },
        'u_and': <String, Object?>{
          'hide_name': 0,
          'type': r'$and',
          'parameters': <String, Object?>{'A_WIDTH': 2, 'B_SIGNED': -1},
          'attributes': <String, Object?>{},
          'connections': <String, Object?>{
            'A': <Object>[6, 7],
            'B': <Object>['z', 'Z'],
            'Y': <Object>[8, 9],
          },
        },
        'u_leaf': <String, Object?>{
          'type': 'leaf',
          'connections': <String, Object?>{
            'a': <Object>[3],
          },
        },
      },
      'memories': <String, Object?>{
        'mem': <String, Object?>{'width': 8, 'size': 1.0e2},
      },
      'netnames': <String, Object?>{
        'clk_a': <String, Object?>{
          'hide_name': 0,
          'bits': <Object>[2],
          'attributes': <String, Object?>{'src': 'rtl/top.sv:2.9-2.14'},
        },
        r'$flatten\u_sync.$q': <String, Object?>{
          'hide_name': 1,
          'bits': <Object>[6, 7],
          'attributes': <String, Object?>{},
        },
        'emoji_\u{1F600}': <String, Object?>{
          'bits': <Object>[8],
        },
      },
    },
    'after': <String, Object?>{
      'attributes': <String, Object?>{'top': '00000001'},
      'cells': <String, Object?>{},
    },
  },
};

/// The module the reader kept, compared field by field with the module the
/// full parser gives, over the fields the reader keeps.
void _expectKeptAsParsed(Module kept, Module parsed) {
  expect(kept.name, parsed.name);
  expect(kept.attributes, parsed.attributes);
  expect(kept.ports, parsed.ports);
  expect(kept.cells.keys, parsed.cells.keys);
  for (final name in parsed.cells.keys) {
    final a = kept.cells[name]!;
    final b = parsed.cells[name]!;
    expect(a.type, b.type, reason: name);
    expect(a.hideName, b.hideName, reason: name);
    expect(a.connections, b.connections, reason: name);
    expect(a.attributes['src'], b.attributes['src'], reason: name);
    expect(
      a.attributes.keys.where((k) => k != 'src'),
      isEmpty,
      reason: 'only src is kept on a cell',
    );
    expect(a.parameters, isEmpty);
    expect(a.portDirections, isEmpty);
  }
  expect(kept.nets.keys, parsed.nets.keys);
  for (final name in parsed.nets.keys) {
    expect(kept.nets[name]!.bits, parsed.nets[name]!.bits, reason: name);
    expect(kept.nets[name]!.hideName, parsed.nets[name]!.hideName);
    expect(kept.nets[name]!.attributes, isEmpty);
  }
}

void main() {
  const reader = CdcNetlistReader();
  const parser = YosysJsonParser();
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('cdc-reader-'));
  tearDown(() => temp.deleteSync(recursive: true));

  File write(String text) =>
      File(p.join(temp.path, 'netlist.json'))..writeAsStringSync(text);

  group('keeps what the parser gives', () {
    final text = const JsonEncoder.withIndent('  ').convert(_document());
    final parsed = parser.parse(text);

    test('the named top module, from a string', () {
      final model = reader.readString(text, topModule: 'top');
      expect(model.creator, parsed.creator);
      expect(model.modules.keys, ['top']);
      _expectKeptAsParsed(model.modules['top']!, parsed.modules['top']!);
    });

    test('the named top module, from a file', () {
      final model = reader.readFile(write(text), topModule: 'top');
      expect(model.modules.keys, ['top']);
      _expectKeptAsParsed(model.modules['top']!, parsed.modules['top']!);
    });

    test('compact JSON reads the same as indented JSON', () {
      final compact = reader.readString(
        jsonEncode(_document()),
        topModule: 'top',
      );
      _expectKeptAsParsed(compact.modules['top']!, parsed.modules['top']!);
    });

    test('a bit is one shared object per net id', () {
      final top = reader.readString(text, topModule: 'top').modules['top']!;
      expect(
        identical(top.ports['clk_a']!.bits.single, top.nets['clk_a']!.bits[0]),
        isTrue,
      );
    });
  });

  group('which module it keeps', () {
    final text = jsonEncode(_document());
    final parsed = parser.parse(text);

    test('with no name, the first top-marked one, as topModule does', () {
      final model = reader.readString(text);
      expect(model.topModule?.name, parsed.topModule?.name);
      expect(model.modules.keys, ['top']);
    });

    test('a named module that is not there leaves the model empty', () {
      expect(reader.readString(text, topModule: 'missing').modules, isEmpty);
    });

    test('a module whose attributes follow its cells is still found', () {
      final attributesLast = jsonEncode(<String, Object?>{
        'modules': <String, Object?>{
          'm': <String, Object?>{
            'cells': <String, Object?>{
              'c': <String, Object?>{
                'type': r'$not',
                'connections': <String, Object?>{
                  'A': <Object>[2],
                  'Y': <Object>[3],
                },
              },
            },
            'attributes': <String, Object?>{'top': 1},
          },
        },
      });
      final model = reader.readString(attributesLast);
      expect(model.topModule?.cells.keys, ['c']);
    });
  });

  group('chunk boundaries', () {
    // The file is read 1 MiB at a time and a string is encoded 256 Ki code
    // units at a time; a token, an escape or a multi-byte character can sit
    // across either boundary.
    String big() {
      final cells = <String, Object?>{};
      for (var i = 0; i < 9000; i++) {
        cells['c$i'] = <String, Object?>{
          'type': r'$and',
          'attributes': <String, Object?>{
            'src': 'répertoire/\u{1F600}\\"x$i".sv:$i.1-$i.9',
          },
          'connections': <String, Object?>{
            'A': <Object>[i + 2],
            'B': <Object>['1'],
            'Y': <Object>[i + 100000],
          },
        };
      }
      return jsonEncode(<String, Object?>{
        'creator': 'big',
        'modules': <String, Object?>{
          'top': <String, Object?>{
            'attributes': <String, Object?>{'top': 1},
            'cells': cells,
          },
        },
      });
    }

    test('a document larger than one chunk reads as the parser reads it', () {
      final text = big();
      expect(utf8.encode(text).length, greaterThan(1 << 20));
      final parsed = parser.parse(text).modules['top']!;
      _expectKeptAsParsed(
        reader.readFile(write(text), topModule: 'top').modules['top']!,
        parsed,
      );
      _expectKeptAsParsed(
        reader.readString(text, topModule: 'top').modules['top']!,
        parsed,
      );
    });
  });

  group('malformed input fails rather than reading as a smaller netlist', () {
    final text = jsonEncode(_document());

    test('a truncated document', () {
      expect(
        () => reader.readFile(write(text.substring(0, text.length ~/ 2))),
        throwsFormatException,
      );
    });

    test('text after the document', () {
      expect(() => reader.readString('$text x'), throwsFormatException);
    });

    test('a cell with no type', () {
      expect(
        () => reader.readString(
          '{"modules":{"top":{"attributes":{"top":1},'
          '"cells":{"c":{"connections":{}}}}}}',
        ),
        throwsFormatException,
      );
    });

    test('a bit that is neither a net id nor a constant', () {
      expect(
        () => reader.readString(
          '{"modules":{"top":{"attributes":{"top":1},'
          '"netnames":{"n":{"bits":["q"]}}}}}',
        ),
        throwsFormatException,
      );
    });

    test('a trailing comma', () {
      expect(
        () => reader.readString('{"modules":{"top":{"cells":{},}}}'),
        throwsFormatException,
      );
    });
  });

  group('CdcEngine reads the netlist from disk', () {
    // A Yosys stand-in that writes the netlist at the runner's own quoted
    // `write_json` path, which the engine asks the runner to keep.
    List<FileSystemEntity> runnerFiles() => temp
        .listSync()
        .where((e) => p.basename(e.path).startsWith('crux_yosys_'))
        .toList();

    test('the netlist is read from the file the runner kept, and the file '
        'is removed', () async {
      final runner = _DiskYosys(jsonEncode(_twoDomainNetlist()));
      final violations = await CdcEngine(
        processRunner: runner,
        tempDirectory: temp,
      ).run(_request(temp.path)).toList();
      expect(runner.written, isNotNull, reason: 'no write_json');
      expect(
        File(runner.written!).existsSync(),
        isFalse,
        reason: 'the netlist file outlived the run',
      );
      expect(runnerFiles(), isEmpty);
      expect(
        violations.where((v) => v.ruleId == 'cdc/unsync-single-bit'),
        hasLength(1),
        reason: 'flag_a in clk_a feeds flag_b in clk_b directly',
      );
    });

    test('a netlist that cannot be read is an analysis failure and its file '
        'is still removed', () async {
      final violations = await CdcEngine(
        processRunner: _DiskYosys('{"modules": '),
        tempDirectory: temp,
      ).run(_request(temp.path)).toList();
      expect(violations.single.ruleId, 'cdc/elaboration-failed');
      expect(violations.single.raw[Violation.analysisFailedKey], isTrue);
      expect(runnerFiles(), isEmpty);
    });
  });
}

LintRunRequest _request(String dir) => LintRunRequest(
  sourceFiles: <String>[p.join(dir, 'top.v')],
  binary: const EngineBinaryConfig.system(),
  language: HdlLanguage.verilog,
  topModule: 'top',
  projectRoot: dir,
);

/// One flop in clk_a driving one in clk_b directly. Written by hand: the
/// unsynchronized crossing is what the structure means.
Map<String, Object?> _twoDomainNetlist() {
  Map<String, Object?> dff(int clk, int d, int q, String src) =>
      <String, Object?>{
        'hide_name': 0,
        'type': r'$dff',
        'attributes': <String, Object?>{'src': src},
        'connections': <String, Object?>{
          'CLK': <Object>[clk],
          'D': <Object>[d],
          'Q': <Object>[q],
        },
      };
  Map<String, Object?> net(List<Object> bits) => <String, Object?>{
    'hide_name': 0,
    'bits': bits,
  };
  return <String, Object?>{
    'creator': 'hand-written',
    'modules': <String, Object?>{
      'top': <String, Object?>{
        'attributes': <String, Object?>{'top': 1},
        'ports': <String, Object?>{
          'clk_a': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[2],
          },
          'clk_b': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[3],
          },
          'd': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[4],
          },
          'q': <String, Object?>{
            'direction': 'output',
            'bits': <Object>[6],
          },
        },
        'cells': <String, Object?>{
          'flag_a': dff(2, 4, 5, '/p/top.v:23.3-23.20'),
          'flag_b': dff(3, 5, 6, '/p/top.v:28.3-28.20'),
        },
        'netnames': <String, Object?>{
          'clk_a': net(<Object>[2]),
          'clk_b': net(<Object>[3]),
          'd': net(<Object>[4]),
          'flag_a': net(<Object>[5]),
          'q': net(<Object>[6]),
        },
      },
    },
  };
}

class _DiskYosys implements ProcessRunner {
  _DiskYosys(this.netlist);

  final String netlist;

  /// The path of the `write_json` statement, where the netlist was written.
  String? written;

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) async {
    if (arguments.length == 1 && arguments.single == '-V') {
      return const ProcessRunResult(
        exitCode: 0,
        stdout: 'Yosys 0.70',
        stderr: '',
      );
    }
    final quoted = RegExp('write_json "([^"]+)"').firstMatch(arguments.last);
    expect(arguments.last, isNot(contains('design -reset')));
    written = quoted!.group(1);
    File(written!).writeAsStringSync(netlist);
    return const ProcessRunResult(exitCode: 0, stdout: '', stderr: '');
  }
}
