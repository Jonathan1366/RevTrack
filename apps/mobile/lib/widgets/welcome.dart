import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import '../core/design.dart';
import '../core/google_auth.dart';
import 'glass_surface.dart';
import 'google_button_stub.dart'
    if (dart.library.js_interop) 'google_button_web.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({
    super.key,
    required this.onDemo,
    required this.auth,
    this.enableVideo = true,
  });
  final Future<void> Function() onDemo;
  final GoogleAuthController auth;
  final bool enableVideo;
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final pages = PageController();
  int current = 0;
  bool paused = false, showingLogin = false, showingDemo = false;
  static const titles = [
    'Armada kamu.\nDalam satu tempat.',
    'Cek energi.\nSiap berangkat.',
    'Lihat posisi.\nAtur perjalanan.',
  ];
  static const descriptions = [
    'Posisi kendaraan, kondisi baterai, dan jadwal operasional. Semua bisa kamu cek dari sini.',
    'Pantau baterai dan bahan bakar sebelum kendaraan berangkat. Rencanakan pengisian saat dibutuhkan.',
    'Telusuri perjalanan dan tinjau peringatan agar tim tahu apa yang perlu ditangani.',
  ];

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  Future<void> login(bool register) async {
    setState(() => showingLogin = true);
    unawaited(widget.auth.prepare());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x88050816),
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (context) => LoginSheet(
        auth: widget.auth,
        register: register,
        onDemo: () {
          Navigator.pop(context);
          unawaited(demo());
        },
      ),
    );
    if (mounted) setState(() => showingLogin = false);
  }

  Future<void> demo() async {
    setState(() => showingDemo = true);
    await widget.onDemo();
    if (mounted) setState(() => showingDemo = false);
  }

  void credits() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (context) => const SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Di balik foto dan video',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 16),
            Text(
              'Video EV: Kindel Media / Pexels\nFoto Tesla Model 3: 04iraq / Pexels',
            ),
            SizedBox(height: 12),
            Text(
              'Gambar kendaraan digunakan untuk pengenalan aplikasi. '
              'Status armada di dalam aplikasi berasal dari data yang ditampilkan, bukan dari video ini.',
              style: TextStyle(color: muted, height: 1.6),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1022),
        body: Stack(
          children: [
            Positioned.fill(
              child: PageView(
                controller: pages,
                onPageChanged: (index) => setState(() => current = index),
                children: [
                  EvMedia(
                    poster: 'assets/media/ev-charging-poster.jpg',
                    video: 'assets/media/ev-charging.mp4',
                    play:
                        widget.enableVideo &&
                        !reduceMotion &&
                        !paused &&
                        !showingLogin &&
                        !showingDemo &&
                        current == 0,
                  ),
                  const EvMedia(
                    poster: 'assets/media/ev-charging.jpg',
                    play: false,
                  ),
                  EvMedia(
                    poster: 'assets/media/ev-fleet.jpg',
                    video: 'assets/media/ev-fleet.mp4',
                    play:
                        widget.enableVideo &&
                        !reduceMotion &&
                        !paused &&
                        !showingLogin &&
                        !showingDemo &&
                        current == 2,
                  ),
                ],
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, .32, .6, 1],
                      colors: [
                        Color(0x77080A1C),
                        Color(0x08080A1C),
                        Color(0xAA080A1C),
                        Color(0xFF080A1C),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, size) {
                  final wide = size.maxWidth >= 850;
                  final horizontal = wide ? 56.0 : 24.0;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      20,
                      horizontal,
                      14,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GlassSurface(
                              dark: true,
                              radius: 18,
                              padding: const EdgeInsets.all(10),
                              child: SvgPicture.asset(
                                'assets/brand/revtrack-mark.svg',
                                width: 28,
                                height: 28,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Flexible(
                              child: Text(
                                'RevTrack',
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 23,
                                  letterSpacing: -.8,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (current != 1 && !reduceMotion)
                              GlassAction(
                                label: paused ? 'Putar video' : 'Jeda video',
                                onPressed: () =>
                                    setState(() => paused = !paused),
                                child: Icon(
                                  paused
                                      ? Icons.play_arrow_rounded
                                      : Icons.pause_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: SingleChildScrollView(
                              child: wide
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Expanded(child: intro(true)),
                                        const SizedBox(width: 70),
                                        SizedBox(width: 360, child: actions()),
                                      ],
                                    )
                                  : ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 480,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          intro(false),
                                          const SizedBox(height: 26),
                                          actions(),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: credits,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            minimumSize: const Size(48, 40),
                          ),
                          child: const Text(
                            'Foto & video · Pexels',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget intro(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'SELAMAT DATANG DI REVTRACK',
        style: TextStyle(
          color: Color(0xFFDBD4F8),
          fontSize: 10,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 14),
      AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomLeft,
          children: [...previous, ?current],
        ),
        child: Text(
          titles[current],
          key: ValueKey(current),
          style: TextStyle(
            color: Colors.white,
            fontSize: wide ? 56 : 38,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
            height: 1.12,
          ),
        ),
      ),
      const SizedBox(height: 15),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 410),
        child: Text(
          descriptions[current],
          style: const TextStyle(
            color: Color(0xFFE0E1E9),
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (index) => Semantics(
            selected: current == index,
            label: 'Pengenalan ${index + 1} dari 3',
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                if (MediaQuery.disableAnimationsOf(context)) {
                  pages.jumpToPage(index);
                } else {
                  pages.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    height: 4,
                    width: current == index ? 32 : 14,
                    decoration: BoxDecoration(
                      color: current == index ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget actions() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassSurface(
        dark: true,
        refract: false,
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Mulai dari sini',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Masuk atau daftar dengan akun Google.',
              style: TextStyle(color: Color(0xFFCFD0DB), fontSize: 12),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => login(false),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: ink,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/brand/google.svg',
                    width: 20,
                    height: 20,
                  ),
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Text(
                      'Masuk dengan Google',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => login(true),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Baru di RevTrack? Daftar'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: demo,
        key: const ValueKey('welcome-demo'),
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Coba demo'),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 17),
          ],
        ),
      ),
    ],
  );
}

/// Only the visible video plays. Posters remain available offline and
/// when playback fails, is paused, or reduced motion is enabled.
class EvMedia extends StatefulWidget {
  const EvMedia({
    super.key,
    required this.poster,
    this.video,
    required this.play,
  });
  final String poster;
  final String? video;
  final bool play;
  @override
  State<EvMedia> createState() => _EvMediaState();
}

class _EvMediaState extends State<EvMedia> with WidgetsBindingObserver {
  VideoPlayerController? controller;
  bool initializing = false, resumed = true, failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sync();
  }

  @override
  void didUpdateWidget(covariant EvMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  Future<void> sync() async {
    if (!widget.play || !resumed) {
      try {
        await controller?.pause();
      } catch (_) {
        /* Keep the poster available. */
      }
      return;
    }
    if (widget.video == null || failed) return;
    if (controller != null) {
      try {
        if (controller!.value.isInitialized) await controller!.play();
      } catch (_) {
        if (mounted) setState(() => failed = true);
      }
      return;
    }
    if (initializing) return;
    initializing = true;
    final next = VideoPlayerController.asset(
      widget.video!,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    controller = next;
    next.addListener(() {
      if (mounted && next.value.hasError && !failed) {
        setState(() => failed = true);
      }
    });
    try {
      await next.initialize().timeout(const Duration(seconds: 12));
      if (!mounted) return;
      await next.setVolume(0);
      await next.setLooping(true);
      if (widget.play && resumed) await next.play();
      if (mounted) setState(() {});
    } catch (_) {
      failed = true;
      if (mounted) setState(() {});
    } finally {
      initializing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    unawaited(sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          widget.poster,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF16192E)),
        ),
        if (controller?.value.isInitialized == true && !failed)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller!.value.size.width,
              height: controller!.value.size.height,
              child: VideoPlayer(controller!),
            ),
          ),
      ],
    ),
  );
}

class LoginSheet extends StatelessWidget {
  const LoginSheet({
    super.key,
    required this.auth,
    required this.register,
    required this.onDemo,
  });
  final GoogleAuthController auth;
  final bool register;
  final VoidCallback onDemo;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: GlassSurface(
        refract: false,
        padding: const EdgeInsets.all(24),
        child: ListenableBuilder(
          listenable: auth,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      auth.account != null
                          ? 'Akun Google terhubung'
                          : register
                          ? 'Daftar di RevTrack'
                          : 'Masuk ke RevTrack',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.6,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: auth.busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (auth.account case final account?) ...[
                const Icon(
                  Icons.check_circle_rounded,
                  size: 42,
                  color: success,
                ),
                const SizedBox(height: 14),
                Text(
                  account.displayName ?? 'Akun Google',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(account.email, style: const TextStyle(color: muted)),
                const SizedBox(height: 14),
                const Text(
                  'Akses armada belum tersedia untuk akun ini. '
                  'Kamu bisa melihat contoh fitur melalui demo.',
                  style: TextStyle(height: 1.6),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: auth.busy ? null : auth.signOut,
                  child: const Text('Ganti akun'),
                ),
              ] else ...[
                Text(
                  register
                      ? 'Gunakan akun Google untuk memulai. Tidak perlu membuat kata sandi baru.'
                      : 'Pilih akun Google yang kamu gunakan untuk mengelola armada.',
                  style: const TextStyle(color: muted, height: 1.6),
                ),
                const SizedBox(height: 24),
                if (kIsWeb && auth.ready)
                  Center(child: googleWebButton())
                else
                  OutlinedButton(
                    onPressed: auth.busy ? null : auth.signIn,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (auth.busy)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          SvgPicture.asset(
                            'assets/brand/google.svg',
                            width: 20,
                            height: 20,
                          ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            auth.busy
                                ? 'Menghubungkan…'
                                : 'Lanjutkan dengan Google',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (auth.message case final message?) ...[
                const SizedBox(height: 18),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: green,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(fontSize: 12, height: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: auth.busy ? null : onDemo,
                child: const Text('Coba demo dulu'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Demo memakai data simulasi dan tidak memerlukan akun.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
