import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_selector/file_selector.dart';
import 'video_player_screen.dart';

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
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    VideoPlayerScreen(
                  videoPath: '', // 빈 경로로 에러 상태 표시
                ),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
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
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                VideoPlayerScreen(
              videoPath: videoPath!,
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
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
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                VideoPlayerScreen(
              videoPath: '', // 빈 경로로 에러 상태 표시
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
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
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // 상단 타이틀
            Padding(
              padding: const EdgeInsets.only(top: 60, bottom: 40),
              child: Column(
                children: [
                  Text(
                    'MOVIE MANAGER',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Frame Extractor',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            // 중앙 카드
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 필름 스트립 아이콘
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // 뒤쪽 필름 스트립
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Icon(
                                Icons.movie_filter,
                                size: 80,
                                color: Colors.blue[200],
                              ),
                            ),
                            // 앞쪽 필름 스트립 (재생 아이콘 포함)
                            Icon(
                              Icons.movie_filter,
                              size: 80,
                              color: Colors.blue[600],
                            ),
                            // 재생 아이콘
                            Icon(
                              Icons.play_circle_filled,
                              size: 40,
                              color: Colors.white,
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        // Select Video 버튼
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue[600]!,
                                  Colors.blue[700]!,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _isLoading ? null : _pickVideo,
                                borderRadius: BorderRadius.circular(12),
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : Text(
                                          'Select Video',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
