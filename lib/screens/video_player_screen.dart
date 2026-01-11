import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoPath;

  const VideoPlayerScreen({
    super.key,
    required this.videoPath,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isSaving = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _dragStartPosition = 0.0;
  Duration _dragStartTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.file(File(widget.videoPath));
    await _controller.initialize();
    setState(() {
      _isInitialized = true;
      _totalDuration = _controller.value.duration;
      _currentPosition = _controller.value.position;
    });

    _controller.addListener(() {
      if (mounted) {
        setState(() {
          _currentPosition = _controller.value.position;
          _isPlaying = _controller.value.isPlaying;
        });
      }
    });
  }

  Future<void> _saveFrame() async {
    if (!_isInitialized) return;

    setState(() => _isSaving = true);

    try {
      // Extract frame from video file at current position
      final uint8list = await VideoThumbnail.thumbnailData(
        video: widget.videoPath,
        timeMs: _currentPosition.inMilliseconds,
        imageFormat: ImageFormat.PNG,
        quality: 100,
      );

      if (uint8list != null) {
        // Save to gallery
        await ImageGallerySaver.saveImage(
          uint8list,
          quality: 100,
          name: 'frame_${DateTime.now().millisecondsSinceEpoch}',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Frame saved successfully!'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        throw Exception('Failed to extract frame');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving frame: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _seekToPosition(Duration position) {
    _controller.seekTo(position);
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStartPosition = details.localPosition.dx;
    _dragStartTime = _currentPosition;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double videoWidth) {
    if (videoWidth <= 0 || _totalDuration == Duration.zero) return;

    final dragDistance = details.localPosition.dx - _dragStartPosition;
    final dragRatio = dragDistance / videoWidth;
    final dragDuration = Duration(
      milliseconds: (dragRatio * _totalDuration.inMilliseconds).round(),
    );

    final newPosition = _dragStartTime + dragDuration;
    final clampedPosition = newPosition < Duration.zero
        ? Duration.zero
        : (newPosition > _totalDuration ? _totalDuration : newPosition);

    _seekToPosition(clampedPosition);
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (hours == '00') {
      return '$minutes:$seconds';
    }
    return '$hours:$minutes:$seconds';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Frame'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isInitialized)
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_alt),
              onPressed: _isSaving ? null : _saveFrame,
              tooltip: 'Save current frame',
            ),
        ],
      ),
      body: _isInitialized
          ? Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Center(
                        child: GestureDetector(
                          onTap: _togglePlayPause,
                          onHorizontalDragStart: _onHorizontalDragStart,
                          onHorizontalDragUpdate: (details) {
                            _onHorizontalDragUpdate(
                              details,
                              constraints.maxWidth,
                            );
                          },
                          child: AspectRatio(
                            aspectRatio: _controller.value.aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(_controller),
                                // Visual feedback when paused
                                if (!_isPlaying)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.3),
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    child: Icon(
                                      Icons.play_arrow,
                                      size: 48,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_currentPosition),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            _formatDuration(_totalDuration),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: Theme.of(context).colorScheme.primary,
                          bufferedColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.3),
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.replay_10),
                            iconSize: 32,
                            onPressed: () {
                              final newPosition = _currentPosition -
                                  const Duration(seconds: 10);
                              _seekToPosition(newPosition < Duration.zero
                                  ? Duration.zero
                                  : newPosition);
                            },
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            child: IconButton(
                              icon: Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow),
                              iconSize: 40,
                              color: Theme.of(context).colorScheme.onPrimary,
                              onPressed: _togglePlayPause,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.forward_10),
                            iconSize: 32,
                            onPressed: () {
                              final newPosition = _currentPosition +
                                  const Duration(seconds: 10);
                              _seekToPosition(newPosition > _totalDuration
                                  ? _totalDuration
                                  : newPosition);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveFrame,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_alt),
                          label: Text(_isSaving
                              ? 'Saving...'
                              : 'Save Current Frame as Photo'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(),
            ),
    );
  }
}
