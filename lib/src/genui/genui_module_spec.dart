import 'package:genui/genui.dart';

/// A genUI module specification produced by the local AI from a user's goal.
///
/// This is the bridge between `flutter_local_ai` and `genui`: the on-device
/// model emits one of these (as JSON), and it can be rendered either through
/// the host app's typed-block renderer ([toModuleJson]) or directly by the
/// `genui` runtime as an A2UI component tree ([toComponents]).
///
/// A module is a stack of typed blocks:
///   note | field | amount | progress | checklist | week | stat | list |
///   lessons | reminder | calc | docs
class GenUiModuleSpec {
  final String title;
  final String icon; // lucide icon name
  final String tone; // fern | apricot | sky | lilac
  final String blurb;
  final List<Map<String, dynamic>> blocks;

  const GenUiModuleSpec({
    required this.title,
    required this.icon,
    required this.tone,
    required this.blurb,
    required this.blocks,
  });

  static const _allowedBlocks = {
    'note', 'field', 'amount', 'progress', 'checklist', 'week', 'stat', 'list',
    'lessons', 'reminder', 'calc', 'docs',
  };
  static const _allowedTones = {'fern', 'apricot', 'sky', 'lilac'};

  /// Parse + validate the JSON the model produced. Returns null if it doesn't
  /// contain at least a title and one valid block (so the caller can fall back).
  static GenUiModuleSpec? tryParse(Map<String, dynamic> json) {
    final title = (json['title'] ?? '').toString().trim();
    if (title.isEmpty) return null;

    final rawBlocks = json['blocks'];
    if (rawBlocks is! List) return null;

    final blocks = <Map<String, dynamic>>[];
    for (final raw in rawBlocks) {
      if (raw is! Map) continue;
      final b = Map<String, dynamic>.from(raw);
      final type = (b['type'] ?? '').toString();
      if (!_allowedBlocks.contains(type)) continue;
      blocks.add(b);
    }
    if (blocks.isEmpty) return null;

    var tone = (json['tone'] ?? 'fern').toString();
    if (!_allowedTones.contains(tone)) tone = 'fern';

    return GenUiModuleSpec(
      title: title.length > 36 ? '${title.substring(0, 34)}…' : title,
      icon: (json['icon'] ?? 'sparkles').toString(),
      tone: tone,
      blurb: (json['blurb'] ?? 'A plan to get this done.').toString(),
      blocks: blocks,
    );
  }

  /// Shape consumed by the host app's `FledgeModule.fromJson`.
  Map<String, dynamic> toModuleJson() => {
        'id': 'gen-${DateTime.now().millisecondsSinceEpoch}',
        'title': title,
        'icon': icon,
        'tone': tone,
        'kind': 'composed',
        'generated': true,
        'aiGenerated': true,
        'blurb': blurb,
        'blocks': blocks,
      };

  /// An A2UI component tree for the `genui` renderer — a compact, faithful
  /// summary of the generated module that `genui`'s `Surface` can build.
  List<Component> toComponents() {
    final children = <String>['gen_header'];
    final components = <Component>[
      Component(id: 'gen_header', type: 'Text',
          properties: {'text': title, 'variant': 'h4'}),
    ];

    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final id = 'gen_block_$i';
      children.add(id);
      components.add(Component(id: id, type: 'Text',
          properties: {'text': _describeBlock(b)}));
    }

    components.insert(
        0, Component(id: 'root', type: 'Column', properties: {'children': children}));
    return components;
  }

  static String _describeBlock(Map<String, dynamic> b) {
    final type = (b['type'] ?? '').toString();
    final label = (b['label'] ?? b['title'] ?? b['text'] ?? type).toString();
    switch (type) {
      case 'amount':
        return '$label: ${b['prefix'] ?? ''}${b['value'] ?? ''}';
      case 'progress':
        return '$label: ${b['prefix'] ?? ''}${b['value'] ?? 0} of '
            '${b['prefix'] ?? ''}${b['target'] ?? 0}';
      case 'reminder':
        return 'Reminder · $label';
      case 'calc':
        return 'Calculator · $label';
      case 'checklist':
        return 'Checklist · ${(b['items'] as List?)?.length ?? 0} steps';
      case 'docs':
        return 'Documents · ${(b['items'] as List?)?.length ?? 0} tracked';
      case 'note':
        return label;
      default:
        return label;
    }
  }
}
