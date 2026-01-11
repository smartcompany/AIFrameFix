import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path/path.dart' as path;
import 'package:macos_file_picker/macos_file_picker.dart';

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
  static const MethodChannel _channel = MethodChannel('video_frame_extractor');

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
    if (!_isInitialized) {
      print('ERROR: 비디오가 초기화되지 않았습니다');
      return;
    }

    print('DEBUG: ===== 프레임 저장 시작 =====');
    setState(() => _isSaving = true);

    try {
      Uint8List? uint8list;

      if (Platform.isMacOS) {
        // macOS에서는 네이티브 AVFoundation 사용
        print('DEBUG: macOS 네이티브 프레임 추출 시작');

        if (_isPlaying) {
          print('DEBUG: 비디오 재생 중, 일시 정지');
          await _controller.pause();
        }

        // 현재 컨트롤러의 정확한 위치를 가져옴
        final currentPosition = _controller.value.position;
        final positionInSeconds = currentPosition.inMilliseconds / 1000.0;

        print('DEBUG: 비디오 파일 경로: ${widget.videoPath}');
        print(
            'DEBUG: 현재 위치: ${currentPosition.inSeconds}초 (${currentPosition.inMilliseconds}ms)');
        print('DEBUG: positionInSeconds: $positionInSeconds');

        try {
          print('DEBUG: 네이티브 extractFrame 호출 시작');
          final String? framePath =
              await _channel.invokeMethod('extractFrame', {
            'videoPath': widget.videoPath,
            'positionInSeconds': positionInSeconds,
          });
          print('DEBUG: 네이티브 extractFrame 완료, framePath: $framePath');

          if (framePath != null) {
            final file = File(framePath);
            if (await file.exists()) {
              uint8list = await file.readAsBytes();
              print('DEBUG: uint8list 생성 완료, 크기: ${uint8list.length} bytes');
              // 임시 파일 삭제
              await file.delete();
              print('DEBUG: 임시 파일 삭제 완료');
            } else {
              print('ERROR: 추출된 프레임 파일이 존재하지 않습니다');
              throw Exception('Extracted frame file not found');
            }
          } else {
            print('ERROR: framePath가 null입니다');
            throw Exception('Frame path is null');
          }
        } catch (e, stackTrace) {
          print('ERROR: 네이티브 extractFrame 에러 발생');
          print('ERROR: 에러 타입: ${e.runtimeType}');
          print('ERROR: 에러 메시지: $e');
          print('ERROR: 스택 트레이스: $stackTrace');
          rethrow;
        }
      } else {
        // iOS/Android에서는 video_thumbnail 사용
        print('DEBUG: iOS/Android 프레임 추출 시작');
        print('DEBUG: 비디오 파일 경로: ${widget.videoPath}');
        print('DEBUG: 현재 위치: ${_currentPosition.inMilliseconds}ms');

        try {
          print('DEBUG: VideoThumbnail.thumbnailData 호출 시작');
          uint8list = await VideoThumbnail.thumbnailData(
            video: widget.videoPath,
            timeMs: _currentPosition.inMilliseconds,
            imageFormat: ImageFormat.PNG,
            quality: 100,
          );
          print(
              'DEBUG: VideoThumbnail.thumbnailData 완료, uint8list: ${uint8list != null ? "존재, 크기: ${uint8list.length} bytes" : "null"}');
        } catch (e, stackTrace) {
          print('ERROR: VideoThumbnail.thumbnailData 에러 발생');
          print('ERROR: 에러 메시지: $e');
          print('ERROR: 스택 트레이스: $stackTrace');
          rethrow;
        }
      }

      if (uint8list != null) {
        print('DEBUG: uint8list 생성 완료, 크기: ${uint8list.length} bytes');

        if (Platform.isMacOS) {
          // macOS에서는 네이티브 파일 저장 다이얼로그 사용 (Save 버튼)
          print('DEBUG: macOS 파일 저장 다이얼로그 시작');
          final currentPosition = _controller.value.position;
          final defaultFileName =
              'frame_${currentPosition.inSeconds}s_${DateTime.now().millisecondsSinceEpoch}.png';
          print('DEBUG: 기본 파일명: $defaultFileName');

          final MacosFilePicker picker = MacosFilePicker();
          print('DEBUG: MacosFilePicker.pick 호출 시작');
          final result = await picker.pick(
            MacosFilePickerMode.saveFile,
            defaultName: defaultFileName,
            allowedFileExtensions: ['png'],
          );
          print(
              'DEBUG: MacosFilePicker.pick 완료, result: ${result?.length ?? 0}개');

          if (result == null || result.isEmpty) {
            // 사용자가 취소한 경우
            print('DEBUG: 사용자가 저장을 취소했습니다');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Save cancelled'),
                  backgroundColor: Colors.orange,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }

          final filePath = result.first.path;
          print('DEBUG: 저장할 파일 경로: $filePath');
          final file = File(filePath);

          print('DEBUG: 파일 쓰기 시작');
          await file.writeAsBytes(uint8list);
          print('DEBUG: 파일 쓰기 완료');

          final savedFileName = path.basename(filePath);
          final savedDirectory = path.dirname(filePath);
          print('DEBUG: 파일 저장 완료: $savedFileName (위치: $savedDirectory)');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Frame saved: $savedFileName\nLocation: $savedDirectory'),
                    ),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        } else {
          // iOS/Android에서는 갤러리에 저장
          print('DEBUG: iOS/Android 갤러리 저장 시작');
          try {
            print('DEBUG: ImageGallerySaver.saveImage 호출 시작');
            await ImageGallerySaver.saveImage(
              uint8list,
              quality: 100,
              name: 'frame_${DateTime.now().millisecondsSinceEpoch}',
            );
            print('DEBUG: ImageGallerySaver.saveImage 완료');

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
          } catch (e, stackTrace) {
            print('ERROR: ImageGallerySaver.saveImage 에러 발생');
            print('ERROR: 에러 메시지: $e');
            print('ERROR: 스택 트레이스: $stackTrace');
            rethrow;
          }
        }
      } else {
        print('ERROR: uint8list가 null입니다 - 프레임 추출 실패');
        throw Exception('Failed to extract frame');
      }
    } catch (e, stackTrace) {
      print('ERROR: ===== 프레임 저장 에러 발생 =====');
      print('ERROR: 에러 타입: ${e.runtimeType}');
      print('ERROR: 에러 메시지: $e');
      print('ERROR: 스택 트레이스: $stackTrace');
      print('ERROR: ================================');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving frame: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      print('DEBUG: finally 블록 실행');
      if (mounted) {
        setState(() => _isSaving = false);
      }
      print('DEBUG: ===== 프레임 저장 종료 =====');
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
