import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../application/downloads/downloads_cubit.dart';
import '../../../application/library/library_cubit.dart';
import '../../../application/player/player_cubit.dart';
import '../../../core/di/locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/storage/app_prefs.dart';
import '../../../domain/entities/source/anime.dart';

/// Fullscreen landscape player (INSTRUCTIONS.md §8).
///
/// The source's headers are passed to libmpv: many sources 403 without a
/// Referer, so this is not optional decoration.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  /// What is currently open, so a rebuild does not restart playback.
  String? _openedUrl;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  /// The player reports a duration of zero until the stream is probed, and
  /// recording that would mark everything as instantly finished.
  Duration _duration = Duration.zero;

  /// Where playback currently is, so switching quality can carry it over.
  Duration _position = Duration.zero;

  /// Where to jump to once playback is genuinely under way.
  ///
  /// libmpv accepts — and then quietly discards — a seek issued while it is
  /// still opening a network stream, and it reports a duration several
  /// seconds before it produces a first position. So neither `Media.start`
  /// nor a seek on the duration event survives. The first non-zero *position*
  /// is the earliest proof that the demuxer is actually running.
  Duration? _pendingSeek;

  /// Captured in `initState`: `dispose` must not reach into the tree for
  /// these, and they never change for the life of this screen.
  late final LibraryCubit _library = context.read<LibraryCubit>();
  late final DownloadsCubit _downloads = context.read<DownloadsCubit>();

  /// "Delete after watching" must fire once, not on every tick past 90%.
  bool _finishNotified = false;
  late final String _animeId;
  late final String _episodeUrl;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    final playback = context.read<PlayerCubit>();
    _animeId = playback.state.anime.id;
    _episodeUrl = playback.state.episode.url;
    playback.resolve();
    _watchPlayback();
  }

  /// Progress is written from here rather than from the controls, so it is
  /// recorded however playback advances — including a seek the user made.
  void _watchPlayback() {
    _durationSub = _player.stream.duration.listen((d) {
      if (d > Duration.zero) _duration = d;
    });
    _positionSub = _player.stream.position.listen((position) {
      if (!mounted) return;
      _position = position;
      if (_duration <= Duration.zero) return;

      final seekTo = _pendingSeek;
      if (seekTo != null) {
        // Wait for playback to actually be moving before jumping.
        if (position <= Duration.zero) return;
        _pendingSeek = null;
        if (seekTo < _duration) {
          unawaited(_player.seek(seekTo));
          // Recording now would write the pre-seek position over the very
          // point being resumed to.
          return;
        }
      }

      unawaited(
        _library.recordProgress(
          animeId: _animeId,
          episodeUrl: _episodeUrl,
          position: position,
          duration: _duration,
        ),
      );

      if (!_finishNotified &&
          (_library.state.progressFor(_animeId, _episodeUrl)?.finished ??
              false)) {
        _finishNotified = true;
        unawaited(_downloads.onEpisodeFinished(_animeId, _episodeUrl));
      }
    });
  }

  /// Null when there is nothing worth resuming — not started, or finished,
  /// in which case a rewatch should begin at the top rather than the credits.
  Duration? _resumePoint() =>
      _library.state.progressFor(_animeId, _episodeUrl)?.resumeAt;

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    // The in-memory position is ahead of what was last written to disk, by up
    // to ten seconds. Backing out of an episode is exactly when that matters.
    unawaited(_library.flush(_animeId, _episodeUrl));
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player.dispose();
    super.dispose();
  }

  Future<void> _open(VideoStream stream) async {
    if (_openedUrl == stream.playbackUrl) return;
    // The first open resumes where the user left off; a later one is a
    // quality switch, which should carry on from where they are rather than
    // start the episode again.
    _pendingSeek = _openedUrl == null ? _resumePoint() : _position;
    _openedUrl = stream.playbackUrl;
    _duration = Duration.zero;

    await _player.open(
      Media(stream.playbackUrl, httpHeaders: stream.headers),
    );
    // External subtitle tracks the source supplied alongside the video.
    final language = locator<AppPrefs>().subtitleLanguage;
    if (language.toLowerCase() == 'off') {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final subtitle = stream.preferredSubtitle(language);
    if (subtitle != null) {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(subtitle.url, title: subtitle.label),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlayerCubit, PlaybackState>(
      listenWhen: (a, b) => a.selected != b.selected,
      listener: (context, state) {
        final stream = state.selected;
        if (stream != null) _open(stream);
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: switch (state.status) {
            PlayerStatus.resolving => _Resolving(state: state),
            PlayerStatus.failure => _Failed(state: state),
            PlayerStatus.ready => _Playing(
              controller: _controller,
              state: state,
            ),
          },
        );
      },
    );
  }
}

class _Resolving extends StatelessWidget {
  const _Resolving({required this.state});
  final PlaybackState state;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Center(child: CircularProgressIndicator()),
      _BackButton(),
      Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 70),
          child: Text(
            'Asking ${state.anime.source.sourceName} for a stream…',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ),
    ],
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.state});
  final PlaybackState state;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.accent,
                  size: 23,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "Couldn't play this episode",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                state.error ?? 'The source gave no reason.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => context.read<PlayerCubit>().resolve(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try again'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.ground,
                ),
              ),
            ],
          ),
        ),
      ),
      _BackButton(),
    ],
  );
}

class _Playing extends StatelessWidget {
  const _Playing({required this.controller, required this.state});

  final VideoController controller;
  final PlaybackState state;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: Video(
          controller: controller,
          controls: AdaptiveVideoControls,
          fit: BoxFit.contain,
        ),
      ),
      _BackButton(),
      if (state.hasChoices)
        Positioned(
          top: 10,
          right: 12,
          child: _QualityMenu(state: state),
        ),
    ],
  );
}

class _QualityMenu extends StatelessWidget {
  const _QualityMenu({required this.state});
  final PlaybackState state;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VideoStream>(
    tooltip: 'Quality',
    color: AppColors.surfaceRaised,
    initialValue: state.selected,
    onSelected: context.read<PlayerCubit>().selectStream,
    itemBuilder: (context) => [
      for (final s in state.streams)
        PopupMenuItem(
          value: s,
          child: Text(
            s.quality.isEmpty ? 'Unnamed stream' : s.quality,
            style: TextStyle(
              color: s == state.selected
                  ? AppColors.accent
                  : AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hd_outlined, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          // Sources write these labels themselves and some are a sentence
          // long ("Dailymotion (English)720p (1280x720) - 2.15 MB/s"), so the
          // chip is capped rather than trusted to be short.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              state.selected?.quality.isNotEmpty == true
                  ? state.selected!.quality
                  : 'Quality',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Positioned(
    top: 6,
    left: 6,
    child: SafeArea(
      child: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ),
  );
}
