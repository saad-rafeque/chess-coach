import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:llamadart/llamadart.dart';

import '../../app/settings.dart';
import 'model_store.dart';

/// Writes text from a system and a user message. The real one runs a GGUF model
/// with llama.cpp; tests use a fake.
abstract interface class TextGenerator {
  Future<String> generate(List<(String role, String text)> messages, {int maxTokens});
  Future<void> dispose();
}

/// llama.cpp through llamadart, on the CPU, in a background isolate.
class LlamaGenerator implements TextGenerator {
  LlamaGenerator._(this._engine);

  static Future<LlamaGenerator> load(File model) async {
    final engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(model.path)),
      params: const ModelParams(contextSize: 1024),
    );
    return LlamaGenerator._(engine);
  }

  final LlamaEngine _engine;

  @override
  Future<String> generate(List<(String, String)> messages, {int maxTokens = 80}) => _engine
      .create(
        [
          for (final (role, text) in messages)
            LlamaChatMessage.fromText(
              role: switch (role) {
                'system' => LlamaChatRole.system,
                'assistant' => LlamaChatRole.assistant,
                _ => LlamaChatRole.user,
              },
              text: text,
            ),
        ],
        params: GenerationParams(maxTokens: maxTokens, temp: 0.3, topP: 0.9, penalty: 1.05),
      )
      .text();

  @override
  Future<void> dispose() => _engine.dispose();
}

const _system = 'You are a warm, encouraging chess coach talking to a beginner. Rewrite the coach\'s note so it '
    'sounds friendly and clear, in one or two short sentences. Keep the meaning and every move, square, piece and '
    'number exactly as written. Never add new moves, squares, pieces or advice. Only reply with the rewritten note.';

/// Worked examples that show the small model what to do.
const _examples = [
  (
    'Now Black can take your knight on f6. Better was Nd5.',
    'Careful: Black can now win your knight on f6. Nd5 was the stronger move.'
  ),
  (
    'You missed Qxh7#, which wins.',
    'So close! Qxh7# was there, and it would have won the game on the spot.'
  ),
  (
    'There was a stronger move. Better was Re1.',
    'Not bad, but Re1 was even stronger.'
  ),
  (
    'This allows checkmate in 3. Better was g3.',
    'Watch out: this lets your opponent force checkmate in 3. g3 would have kept you safe.'
  ),
];

/// The chat messages for rephrasing [facts].
List<(String, String)> rephrasePrompt(String facts) => [
      ('system', _system),
      for (final (note, reply) in _examples) ...[('user', 'Note: $note'), ('assistant', reply)],
      ('user', 'Note: $facts'),
    ];

final _move = RegExp(r'\b(?:O-O(?:-O)?|[KQRBN][a-h]?[1-8]?x?[a-h][1-8]|[a-h]x[a-h][1-8](?:=[QRBN])?)');
final _square = RegExp(r'\b[a-h][1-8]\b');
final _number = RegExp(r'\b\d+\b');
final _meta = RegExp(r"\b(sorry|request|clarify|mentioned|provide|assist|note|AI|I'm|I am|I)\b", caseSensitive: false);
final _word = RegExp(r'\b(king|queen|rook|bishop|knight|pawn|white|black|checkmate|mate|stalemate)s?\b',
    caseSensitive: false);

Set<String> _all(RegExp r, String s) => {for (final m in r.allMatches(s)) m.group(0)!.toLowerCase()};

bool _same(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

final _praise = RegExp(r'\b(correct|right|great|excellent|well done|good move|nice|perfect)\b', caseSensitive: false);

/// Piece, colour and mate words, singular, with "checkmate" counted as "mate".
Set<String> _words(String s) => {
      for (final w in _all(_word, s)) w.replaceFirst(RegExp(r's$'), '').replaceFirst('checkmate', 'mate'),
    };

/// Cleans the model's answer and checks it says nothing the facts don't say: every
/// move, square, number and piece name must come from [facts], and the moves in
/// [facts] must all still be there. Returns null when the answer can't be trusted.
String? acceptRephrase(String facts, String answer) {
  var out = answer.trim();
  if (out.toLowerCase().startsWith('note:')) out = out.substring(5).trim();
  out = out.replaceAll(RegExp(r'^["“]|["”]$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (out.isEmpty || out.length > facts.length * 1.8 + 60) return null;
  // Small models sometimes talk about the task instead of doing it.
  if (out.contains('?') || _meta.hasMatch(out)) return null;
  // Exact case for moves (Nf3 vs nf3), lower case for the rest.
  final factMoves = {for (final m in _move.allMatches(facts)) m.group(0)!};
  final outMoves = {for (final m in _move.allMatches(out)) m.group(0)!};
  if (!factMoves.containsAll(outMoves) || !outMoves.containsAll(factMoves)) return null;
  if (!_all(_square, facts).containsAll(_all(_square, out))) return null;
  // Numbers, pieces, sides and mate threats must all survive, and nothing new may appear.
  if (!_same(_all(_number, facts), _all(_number, out)) || !_same(_words(facts), _words(out))) return null;
  // The notes explain errors, so praise means the model misread them.
  if (_praise.hasMatch(out)) return null;
  return out;
}

/// The coach's optional friendly voice: rephrases engine-based explanations with a
/// small local language model. Every caller keeps its template text as the fallback,
/// so the app never needs the model.
class CoachVoice extends ChangeNotifier {
  CoachVoice({
    required this.settings,
    required this.models,
    Future<TextGenerator> Function(File model)? loader,
    this.timeout = const Duration(seconds: 25),
  }) : _loader = loader ?? LlamaGenerator.load {
    settings.addListener(_onSettings);
  }

  /// A voice that never speaks (tests, or before the app has loaded).
  CoachVoice.off()
      : settings = AppSettings.memory()..friendlyVoice = false,
        models = ModelStore(),
        _loader = LlamaGenerator.load,
        timeout = Duration.zero;

  final AppSettings settings;
  final ModelStore models;
  final Future<TextGenerator> Function(File model) _loader;
  final Duration timeout;

  TextGenerator? _generator;
  String? _loadedId;
  Future<TextGenerator?>? _loading;
  Future<void> _queue = Future.value();
  final _cache = LinkedHashMap<String, String?>();
  bool _failed = false;

  ModelSpec get model => modelById(settings.voiceModel);

  /// True when explanations will be rephrased.
  bool get active =>
      settings.friendlyVoice && models.status(model) == ModelStatus.ready && !_failed && timeout > Duration.zero;

  /// Whether the model could not be started on this device.
  bool get failed => _failed;

  void _onSettings() {
    if (_loadedId != null && (!settings.friendlyVoice || _loadedId != model.id)) unawaited(unload());
  }

  Future<TextGenerator?> _ensureLoaded() {
    if (_generator != null && _loadedId == model.id) return Future.value(_generator);
    return _loading ??= () async {
      try {
        final spec = model;
        await models.verifyForLoad(spec);
        final g = await _loader(await models.fileFor(spec));
        _generator = g;
        _loadedId = spec.id;
        return g;
      } catch (e) {
        debugPrint('Coach voice unavailable: $e');
        _failed = true;
        notifyListeners();
        return null;
      } finally {
        _loading = null;
      }
    }();
  }

  /// A friendlier version of [facts], or null to keep the template text.
  Future<String?> polish(String facts) {
    if (!active) return Future.value(null);
    if (_cache.containsKey(facts)) return Future.value(_cache[facts]);
    final result = _queue.then((_) => _run(facts));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<String?> _run(String facts) async {
    if (!active) return null;
    if (_cache.containsKey(facts)) return _cache[facts];
    try {
      final g = await _ensureLoaded();
      if (g == null) return null;
      final answer = await g.generate(rephrasePrompt(facts)).timeout(timeout);
      final ok = acceptRephrase(facts, answer);
      _cache[facts] = ok;
      if (_cache.length > 200) _cache.remove(_cache.keys.first);
      return ok;
    } catch (e) {
      debugPrint('Coach voice skipped: $e');
      return null;
    }
  }

  /// Frees the model's memory (it loads again on the next explanation).
  Future<void> unload() async {
    final g = _generator;
    _generator = null;
    _loadedId = null;
    await g?.dispose();
  }

  /// After deleting or re-downloading a model, try it again.
  void reset() {
    _failed = false;
    _cache.clear();
    unawaited(unload());
    notifyListeners();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    unawaited(unload());
    super.dispose();
  }
}

/// Gives widgets the app's [CoachVoice].
class VoiceScope extends InheritedNotifier<CoachVoice> {
  const VoiceScope({super.key, required CoachVoice voice, required super.child}) : super(notifier: voice);

  static CoachVoice of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<VoiceScope>()!.notifier!;

  static CoachVoice read(BuildContext context) => context.getInheritedWidgetOfExactType<VoiceScope>()!.notifier!;
}
