import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/groups_service.dart';
import '../services/screen_protection_service.dart';
import '../theme/app_theme.dart';

/// مشغل فيديو/تسجيل جلسة داخل التطبيق: رابط مؤقت من الخادم + علامة مائية متحركة + منع التصوير.
class GroupVideoScreen extends StatefulWidget {
  final String groupId;
  final String kind; // videos | recordings
  final String itemId;
  final String title;
  const GroupVideoScreen({super.key, required this.groupId, required this.kind, required this.itemId, required this.title});

  @override
  State<GroupVideoScreen> createState() => _GroupVideoScreenState();
}

class _GroupVideoScreenState extends State<GroupVideoScreen> {
  final _protection = ScreenProtectionService();
  VideoPlayerController? _c;
  GroupMedia? _media;
  String? _error;
  Timer? _wmTimer;
  Alignment _wmAlign = Alignment.topLeft;
  final _rnd = Random();

  @override
  void initState() {
    super.initState();
    _protection.enable();
    _load();
    _wmTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) setState(() => _wmAlign = Alignment(_rnd.nextDouble() * 1.6 - .8, _rnd.nextDouble() * 1.6 - .8));
    });
  }

  Future<void> _load() async {
    try {
      final svc = GroupsService();
      final m = widget.kind == 'admin'
          ? await svc.getAdminRecordingMedia(widget.itemId)
          : await svc.getMedia(groupId: widget.groupId, kind: widget.kind, id: widget.itemId);
      final c = VideoPlayerController.networkUrl(Uri.parse(m.url));
      await c.initialize();
      await c.play();
      if (!mounted) { await c.dispose(); return; }
      setState(() { _media = m; _c = c; });
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر تشغيل المحتوى. تأكد أنك عضو في المجموعة وحاول مرة أخرى.');
    }
  }

  @override
  void dispose() {
    _wmTimer?.cancel();
    _c?.dispose();
    _protection.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(title: Text(widget.title), backgroundColor: AppColors.ink, foregroundColor: Colors.white),
      body: Center(
        child: _error != null
            ? Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center))
            : (c == null || !c.value.isInitialized)
                ? const CircularProgressIndicator(color: AppColors.gold)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: Stack(
                          children: [
                            GestureDetector(onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()), child: VideoPlayer(c)),
                            IgnorePointer(
                              child: AnimatedAlign(
                                duration: const Duration(seconds: 2),
                                alignment: _wmAlign,
                                child: Text(_media?.watermarkText ?? '', style: const TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: AppColors.gold)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(onPressed: () => c.seekTo(c.value.position - const Duration(seconds: 10)), icon: const Icon(Icons.replay_10, color: Colors.white)),
                          IconButton(onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play()), icon: Icon(c.value.isPlaying ? Icons.pause_circle : Icons.play_circle, color: AppColors.gold, size: 38)),
                          IconButton(onPressed: () => c.seekTo(c.value.position + const Duration(seconds: 10)), icon: const Icon(Icons.forward_10, color: Colors.white)),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}
