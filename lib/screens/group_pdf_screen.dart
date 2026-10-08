import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import '../services/groups_service.dart';
import '../services/screen_protection_service.dart';
import '../theme/app_theme.dart';

enum _Tool { browse, pen, highlight, eraser, text }

class _Stroke {
  final int color;
  final double width; // نسبة من عرض الصفحة
  final bool highlight;
  final List<Offset> points; // مُطبَّعة 0..1
  _Stroke(this.color, this.width, this.highlight, this.points);

  Map<String, dynamic> toMap() => {
        'c': color,
        'w': width,
        'h': highlight,
        'p': [for (final o in points) ...[double.parse(o.dx.toStringAsFixed(4)), double.parse(o.dy.toStringAsFixed(4))]],
      };

  static _Stroke fromMap(Map m) {
    final raw = (m['p'] as List?) ?? const [];
    final pts = <Offset>[];
    for (var i = 0; i + 1 < raw.length; i += 2) {
      pts.add(Offset((raw[i] as num).toDouble(), (raw[i + 1] as num).toDouble()));
    }
    return _Stroke((m['c'] as num?)?.toInt() ?? 0xFFE53935, (m['w'] as num?)?.toDouble() ?? 0.004, m['h'] == true, pts);
  }
}

class _Note {
  final Offset pos;
  String text;
  _Note(this.pos, this.text);
}

/// قارئ PDF داخل التطبيق مع: رسم/كتابة، تحديد (هايلايت)، تعليقات نصية، ممحاة، وحفظ تلقائي للمذاكرة لاحقًا.
/// الملاحظات تُحفظ لكل مستخدم في users/{uid}/pdfNotes ولا يراها غيره، وتعود تلقائيًا عند فتح الملف مرة أخرى.
class GroupPdfScreen extends StatefulWidget {
  final String groupId;
  final String fileId;
  final String title;
  const GroupPdfScreen({super.key, required this.groupId, required this.fileId, required this.title});

  @override
  State<GroupPdfScreen> createState() => _GroupPdfScreenState();
}

class _GroupPdfScreenState extends State<GroupPdfScreen> {
  final _protection = ScreenProtectionService();
  PdfDocument? _doc;
  GroupMedia? _media;
  String? _error;
  _Tool _tool = _Tool.browse;
  Color _color = const Color(0xFFE53935);
  final List<Color> _colors = const [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFFEB3B), Color(0xFF212121)];
  final Map<int, _PageState> _states = {};
  int _saving = 0;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _protection.enable();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await GroupsService().getMedia(groupId: widget.groupId, kind: 'files', id: widget.fileId);
      final res = await http.get(Uri.parse(m.url));
      if (res.statusCode != 200) throw Exception('download ${res.statusCode}');
      final doc = await PdfDocument.openData(Uint8List.fromList(res.bodyBytes));
      if (!mounted) return;
      setState(() { _media = m; _doc = doc; });
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر فتح الملف. تأكد أنك عضو في المجموعة وحاول مرة أخرى.');
    }
  }

  @override
  void dispose() {
    for (final s in _states.values) { s.flushNow(); }
    _doc?.close();
    _protection.disable();
    super.dispose();
  }

  _PageState _stateFor(int page) => _states.putIfAbsent(page, () => _PageState(uid: _uid, groupId: widget.groupId, fileId: widget.fileId, page: page, onSaving: (d) { if (mounted) setState(() => _saving += d); }));

  Future<void> _saveAll() async {
    for (final s in _states.values) { await s.flushNow(); }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ ملاحظاتك للمذاكرة')));
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final drawing = _tool == _Tool.pen || _tool == _Tool.highlight || _tool == _Tool.eraser;
    return Scaffold(
      backgroundColor: Colors.grey.shade300,
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_saving > 0) const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          IconButton(tooltip: 'حفظ', icon: const Icon(Icons.save_outlined), onPressed: doc == null ? null : _saveAll),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
          : doc == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  physics: drawing ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(8),
                  cacheExtent: 1500,
                  itemCount: doc.pagesCount,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PdfPageView(
                      key: ValueKey('p${i + 1}'),
                      doc: doc,
                      pageNumber: i + 1,
                      state: _stateFor(i + 1),
                      tool: _tool,
                      color: _color,
                      watermark: _media?.watermarkText ?? '',
                    ),
                  ),
                ),
      bottomNavigationBar: doc == null
          ? null
          : SafeArea(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _toolBtn(_Tool.browse, Icons.pan_tool_alt_outlined, 'تصفح'),
                      _toolBtn(_Tool.pen, Icons.edit, 'قلم'),
                      _toolBtn(_Tool.highlight, Icons.border_color, 'تحديد'),
                      _toolBtn(_Tool.text, Icons.text_fields, 'تعليق'),
                      _toolBtn(_Tool.eraser, Icons.cleaning_services_outlined, 'ممحاة'),
                      const SizedBox(width: 8),
                      for (final c in _colors)
                        GestureDetector(
                          onTap: () => setState(() => _color = c),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 28, height: 28,
                            decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: _color == c ? AppColors.ink : Colors.grey.shade400, width: _color == c ? 3 : 1)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _toolBtn(_Tool t, IconData icon, String label) {
    final on = _tool == t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ChoiceChip(
        avatar: Icon(icon, size: 18, color: on ? Colors.white : AppColors.ink),
        label: Text(label, style: TextStyle(color: on ? Colors.white : AppColors.ink)),
        selected: on,
        selectedColor: AppColors.primaryDark,
        showCheckmark: false,
        onSelected: (_) => setState(() => _tool = t),
      ),
    );
  }
}

/// حالة تعليقات صفحة واحدة + حفظ مؤجل في Firestore.
class _PageState {
  final String uid, groupId, fileId;
  final int page;
  final void Function(int delta) onSaving;
  final List<_Stroke> strokes = [];
  final List<_Note> notes = [];
  final ValueNotifier<int> version = ValueNotifier(0);
  Timer? _timer;
  bool _loaded = false;
  bool _dirty = false;

  _PageState({required this.uid, required this.groupId, required this.fileId, required this.page, required this.onSaving});

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('pdfNotes').doc('${groupId}_${fileId}_$page');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final snap = await _ref.get();
      final d = snap.data();
      if (d != null) {
        strokes..clear()..addAll(((d['strokes'] as List?) ?? const []).map((e) => _Stroke.fromMap(e as Map)));
        notes..clear()..addAll(((d['notes'] as List?) ?? const []).map((e) {
          final m = e as Map;
          return _Note(Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble()), (m['t'] ?? '').toString());
        }));
        version.value++;
      }
    } catch (_) {}
  }

  void changed() {
    version.value++;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 900), flushNow);
  }

  Future<void> flushNow() async {
    _timer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    onSaving(1);
    try {
      if (strokes.isEmpty && notes.isEmpty) {
        await _ref.delete();
      } else {
        await _ref.set({
          'groupId': groupId, 'fileId': fileId, 'page': page,
          'strokes': strokes.map((s) => s.toMap()).toList(),
          'notes': notes.map((n) => {'x': n.pos.dx, 'y': n.pos.dy, 't': n.text}).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      _dirty = true;
    } finally {
      onSaving(-1);
    }
  }
}

class _PdfPageView extends StatefulWidget {
  final PdfDocument doc;
  final int pageNumber;
  final _PageState state;
  final _Tool tool;
  final Color color;
  final String watermark;
  const _PdfPageView({super.key, required this.doc, required this.pageNumber, required this.state, required this.tool, required this.color, required this.watermark});

  @override
  State<_PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<_PdfPageView> {
  Uint8List? _bytes;
  double _ratio = 0.707;
  List<Offset>? _current;

  @override
  void initState() {
    super.initState();
    widget.state.load();
    _render();
  }

  Future<void> _render() async {
    try {
      final page = await widget.doc.getPage(widget.pageNumber);
      final img = await page.render(width: page.width * 2, height: page.height * 2, format: PdfPageImageFormat.jpeg, backgroundColor: '#FFFFFF', quality: 85);
      final ratio = page.height / page.width;
      await page.close();
      if (mounted && img != null) setState(() { _bytes = img.bytes; _ratio = ratio; });
    } catch (_) {}
  }

  Offset _norm(Offset local, Size size) => Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));

  void _eraseAt(Offset p) {
    final s = widget.state;
    final before = s.strokes.length;
    s.strokes.removeWhere((st) => st.points.any((q) => (q - p).distance < 0.025));
    if (s.strokes.length != before) s.changed();
  }

  Future<void> _editNote(_Note? existing, Offset pos) async {
    final ctrl = TextEditingController(text: existing?.text ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'تعليق جديد' : 'تعديل التعليق'),
        content: TextField(controller: ctrl, maxLines: 4, autofocus: true, decoration: const InputDecoration(hintText: 'اكتب ملاحظتك...')),
        actions: [
          if (existing != null) TextButton(onPressed: () => Navigator.pop(context, '\u0000delete'), child: const Text('حذف', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (result == null) return;
    final s = widget.state;
    if (result == '\u0000delete') {
      s.notes.remove(existing);
    } else if (result.trim().isNotEmpty) {
      if (existing != null) { existing.text = result.trim(); } else { s.notes.add(_Note(pos, result.trim())); }
    }
    s.changed();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxWidth * _ratio);
      final tool = widget.tool;
      final drawing = tool == _Tool.pen || tool == _Tool.highlight;
      return Container(
        width: size.width, height: size.height,
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)]),
        child: _bytes == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  Positioned.fill(child: Image.memory(_bytes!, fit: BoxFit.fill, gaplessPlayback: true)),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (tool == _Tool.pen || tool == _Tool.highlight || tool == _Tool.eraser)
                          ? (d) {
                              final p = _norm(d.localPosition, size);
                              if (tool == _Tool.eraser) { _eraseAt(p); } else { setState(() => _current = [p]); }
                            }
                          : null,
                      onPanUpdate: (tool == _Tool.pen || tool == _Tool.highlight || tool == _Tool.eraser)
                          ? (d) {
                              final p = _norm(d.localPosition, size);
                              if (tool == _Tool.eraser) { _eraseAt(p); return; }
                              final cur = _current;
                              if (cur != null && (cur.last - p).distance > 0.002) setState(() => cur.add(p));
                            }
                          : null,
                      onPanEnd: drawing
                          ? (_) {
                              final cur = _current;
                              if (cur != null && cur.length > 1) {
                                widget.state.strokes.add(_Stroke(widget.color.value, tool == _Tool.highlight ? 0.028 : 0.004, tool == _Tool.highlight, List.of(cur)));
                                widget.state.changed();
                              }
                              setState(() => _current = null);
                            }
                          : null,
                      onTapUp: tool == _Tool.text ? (d) => _editNote(null, _norm(d.localPosition, size)) : null,
                      child: ValueListenableBuilder<int>(
                        valueListenable: widget.state.version,
                        builder: (_, __, ___) => CustomPaint(
                          size: size,
                          painter: _InkPainter(widget.state.strokes, _current, widget.color, tool == _Tool.highlight),
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: widget.state.version,
                    builder: (_, __, ___) => Stack(
                      children: [
                        for (final n in widget.state.notes)
                          Positioned(
                            left: (n.pos.dx * size.width).clamp(0.0, size.width - 28),
                            top: (n.pos.dy * size.height).clamp(0.0, size.height - 28),
                            child: GestureDetector(
                              onTap: () => _editNote(n, n.pos),
                              child: Tooltip(
                                message: n.text,
                                child: Container(
                                  constraints: BoxConstraints(maxWidth: size.width * 0.5),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: const Color(0xFFFFF59D), borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black26)]),
                                  child: Text(n.text, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Transform.rotate(angle: -0.5, child: Text(widget.watermark, style: const TextStyle(color: Color(0x14000000), fontSize: 26, fontWeight: FontWeight.bold))),
                    ),
                  ),
                ],
              ),
      );
    });
  }
}

class _InkPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final List<Offset>? current;
  final Color color;
  final bool highlight;
  _InkPainter(this.strokes, this.current, this.color, this.highlight);

  void _draw(Canvas canvas, Size size, List<Offset> pts, Color c, double w, bool hl) {
    if (pts.isEmpty) return;
    final paint = Paint()
      ..color = hl ? c.withOpacity(0.35) : c
      ..strokeWidth = w * size.width
      ..strokeCap = hl ? StrokeCap.butt : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts.first.dx * size.width, pts.first.dy * size.height);
    for (final p in pts.skip(1)) { path.lineTo(p.dx * size.width, p.dy * size.height); }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) { _draw(canvas, size, s.points, Color(s.color), s.width, s.highlight); }
    final cur = current;
    if (cur != null) _draw(canvas, size, cur, color, highlight ? 0.028 : 0.004, highlight);
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}
