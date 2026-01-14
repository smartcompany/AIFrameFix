import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_selector/file_selector.dart';
import 'video_player_screen.dart';
import 'icon_processor_screen.dart';

class VideoSelectionScreen extends StatefulWidget {
  const VideoSelectionScreen({super.key});

  @override
  State<VideoSelectionScreen> createState() => _VideoSelectionScreenState();
}

class _VideoSelectionScreenState extends State<VideoSelectionScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _requestPermissions() async {
    // macOS에서는 image_picker가 파일 선택 다이얼로그를 사용하므로 권한 요청 불필요
    if (Platform.isMacOS) {
      return;
    }
    await [
      Permission.photos,
      Permission.videos,
      Permission.storage,
    ].request();
  }

  Future<void> _pickVideo() async {
    try {
      setState(() => _isLoading = true);
      print('DEBUG: _pickVideo 시작');

      String? videoPath;

      if (Platform.isMacOS) {
        print('DEBUG: macOS에서 파일 선택 다이얼로그 열기');
        try {
          const XTypeGroup videoTypeGroup = XTypeGroup(
            label: 'videos',
            extensions: ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'],
          );
          print('DEBUG: openFile 호출 전');
          final XFile? file = await openFile(
            acceptedTypeGroups: [videoTypeGroup],
          );
          print('DEBUG: openFile 완료, file: ${file?.path}');
          videoPath = file?.path;
        } catch (e, stackTrace) {
          print('DEBUG: openFile 에러: $e');
          print('DEBUG: stackTrace: $stackTrace');
          rethrow;
        }
      } else {
        print('DEBUG: iOS/Android에서 image_picker 사용');
        await _requestPermissions();

        try {
          // iOS/Android에서 image_picker 사용
          final XFile? video = await _picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(hours: 1),
          );
          videoPath = video?.path;
        } catch (e) {
          print('DEBUG: pickVideo 에러: $e');
          final errorMessage = e.toString();
          // 특정 비디오 형식 에러인 경우에도 플레이어 화면으로 이동
          final isSpecificFormatError =
              errorMessage.contains('invalid_image') ||
                  errorMessage.contains('quicktime-movie') ||
                  errorMessage.contains('NSItemProviderErrorDomain');

          if (isSpecificFormatError && mounted) {
            // 에러가 발생해도 플레이어 화면으로 이동 (에러 상태로)
            print('DEBUG: 에러 발생했지만 플레이어 화면으로 이동');
            // 먼저 플레이어 화면으로 이동
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(
                  videoPath: '', // 빈 경로로 에러 상태 표시
                ),
              ),
            ).then((_) {
              // 플레이어 화면으로 이동한 후 스낵바 표시
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('일부 비디오 형식은 지원되지 않을 수 있습니다. 다른 비디오를 선택해주세요.'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            });
            return;
          } else {
            // 다른 에러는 플레이어 화면으로 이동하지 않고 스낵바만 표시
            rethrow;
          }
        }
      }

      print('DEBUG: videoPath: $videoPath');
      if (videoPath != null && mounted) {
        print('DEBUG: 비디오 플레이어 화면으로 이동');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(
              videoPath: videoPath!,
            ),
          ),
        );
      } else {
        print('DEBUG: 파일 선택 취소 또는 videoPath가 null');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('비디오를 선택하지 않았습니다.'),
              backgroundColor: Colors.grey,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('DEBUG: _pickVideo 에러: $e');
      // 에러가 발생해도 플레이어 화면으로 이동
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(
              videoPath: '', // 빈 경로로 에러 상태 표시
            ),
          ),
        ).then((_) {
          // 플레이어 화면으로 이동한 후 스낵바 표시
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '비디오 선택 중 오류가 발생했습니다: ${e.toString().split(':').first}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        });
      }
    } finally {
      print('DEBUG: finally 블록 실행, 로딩 상태 해제');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.video_library_rounded,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'Movie Manager',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Extract frames from your videos\nand save them as photos',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: 64),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickVideo,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_library_rounded),
                      label: Text(
                        _isLoading ? 'Loading...' : 'Select Video from Gallery',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 4,
                        shadowColor: Colors.black.withOpacity(0.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  if (Platform.isMacOS) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const IconProcessorScreen(),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text(
                          'Remove Icon Borders',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
