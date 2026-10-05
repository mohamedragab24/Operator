
import 'package:flutter/material.dart';
import '../services/api_functions.dart';

class R2Image extends StatefulWidget {
  final String source;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const R2Image({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<R2Image> createState() => _R2ImageState();
}

class _R2ImageState extends State<R2Image> {
  static final Map<String, String> _cache = {};
  String? _url;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant R2Image oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _url = null;
      _failed = false;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    if (widget.source.isEmpty) return;
    if (!widget.source.startsWith('r2cover:') && !widget.source.startsWith('r2:')) {
      if (mounted) setState(() => _url = widget.source);
      return;
    }
    final cached = _cache[widget.source];
    if (cached != null) {
      if (mounted) setState(() => _url = cached);
      return;
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getR2MediaUrl');
      final result = await callable.call<Map<String, dynamic>>({'token': widget.source});
      final url = (result.data['url'] ?? '').toString();
      if (url.isEmpty) throw Exception('empty R2 URL');
      _cache[widget.source] = url;
      if (mounted) setState(() => _url = url);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.errorWidget ?? const SizedBox.shrink();
    if (_url == null) return widget.placeholder ?? const Center(child: CircularProgressIndicator());
    return Image.network(_url!, fit: widget.fit, errorBuilder: (_, __, ___) {
      return widget.errorWidget ?? const SizedBox.shrink();
    });
  }
}
