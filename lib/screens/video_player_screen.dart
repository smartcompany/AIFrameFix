import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path/path.dart' as path;
import 'package:macos_file_picker/macos_file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'dart:ui' as ui;
import 'settings_screen.dart';
import '../services/ad_service.dart';

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
  static const MethodChannel _fileSaveChannel = MethodChannel('file_saver');

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isSaving = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _isContinuousSeeking = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  List<ui.Image?> _thumbnailImages = [];
  bool _isLoadingThumbnails = false;
  int? _videoWidth;
  int? _videoHeight;
  double? _frameRate;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      // 빈 경로인 경우 에러 상태로 설정
      if (widget.videoPath.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = '비디오 파일이 선택되지 않았습니다.';
          _isInitialized = false;
        });
        return;
      }

      _controller = VideoPlayerController.file(File(widget.videoPath));
      await _controller!.initialize();

      setState(() {
        _isInitialized = true;
        _hasError = false;
        _totalDuration = _controller!.value.duration;
        _currentPosition = _controller!.value.position;
        _videoWidth = _controller!.value.size.width.toInt();
        _videoHeight = _controller!.value.size.height.toInt();
        _frameRate = _controller!.value.size.width > 0
            ? 30.0 // 기본값, 실제로는 비디오에서 가져와야 함
            : null;
      });

      _controller!.addListener(() {
        if (mounted && _controller != null) {
          setState(() {
            _currentPosition = _controller!.value.position;
            _isPlaying = _controller!.value.isPlaying;
          });
        }
      });

      // 썸네일 생성
      _generateThumbnails();
    } catch (e) {
      print('ERROR: 비디오 초기화 실패: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isInitialized = false;
        });
      }
    }
  }

  Future<void> _generateThumbnails() async {
    if (_totalDuration == Duration.zero || widget.videoPath.isEmpty) return;

    setState(() => _isLoadingThumbnails = true);

    try {
      // 적당한 개수의 썸네일 생성 (겹치지 않도록)
      // 벤치마킹 UI처럼 적당한 간격으로 배치 (최대 6-8개)
      final maxThumbnails = 8;
      final videoLengthSeconds = _totalDuration.inSeconds;
      final thumbnailCount = videoLengthSeconds < 15
          ? (videoLengthSeconds / 2).ceil().clamp(4, maxThumbnails)
          : maxThumbnails;

      final List<ui.Image?> thumbnails = [];

      for (int i = 0; i < thumbnailCount; i++) {
        // 첫 번째와 마지막도 포함하도록 시간 계산
        // 0부터 시작해서 마지막까지 균등 분배
        final ratio = thumbnailCount > 1 ? i / (thumbnailCount - 1) : 0.5;

        // 마지막 프레임 근처일 때는 약간 앞으로 이동 (비디오 끝은 프레임이 없을 수 있음)
        var timeMs = (_totalDuration.inMilliseconds * ratio).round();
        if (timeMs >= _totalDuration.inMilliseconds - 100) {
          timeMs = _totalDuration.inMilliseconds - 100;
        }
        timeMs = timeMs.clamp(0, _totalDuration.inMilliseconds - 100);

        try {
          final thumbnailData = await VideoThumbnail.thumbnailData(
            video: widget.videoPath,
            timeMs: timeMs,
            imageFormat: ImageFormat.PNG,
            quality: 75,
          );

          if (thumbnailData != null) {
            final codec = await ui.instantiateImageCodec(thumbnailData);
            final frame = await codec.getNextFrame();
            thumbnails.add(frame.image);
          } else {
            print('WARNING: 썸네일 데이터가 null입니다 (index: $i, timeMs: $timeMs)');
            // 마지막 썸네일이 실패하면 이전 프레임 사용
            if (i == thumbnailCount - 1 && thumbnails.isNotEmpty) {
              thumbnails.add(thumbnails.last);
              print('DEBUG: 마지막 썸네일 실패, 이전 프레임 사용');
            } else {
              thumbnails.add(null);
            }
          }
        } catch (e) {
          print('ERROR: 썸네일 생성 실패 (index: $i, timeMs: $timeMs): $e');
          // 마지막 썸네일이 실패하면 이전 프레임 사용
          if (i == thumbnailCount - 1 && thumbnails.isNotEmpty) {
            thumbnails.add(thumbnails.last);
            print('DEBUG: 마지막 썸네일 생성 실패, 이전 프레임 사용');
          } else {
            thumbnails.add(null);
          }
        }
      }

      if (mounted) {
        setState(() {
          _thumbnailImages = thumbnails;
          _isLoadingThumbnails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingThumbnails = false);
      }
    }
  }

  void _showSaveOptionsDialog(
      Uint8List imageData, String imageFormat, int quality) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('저장 방법 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.purple),
              title: const Text('광고보고 앨범에 저장'),
              onTap: () {
                Navigator.pop(context);
                _showAdAndSaveToGallery(imageData, quality);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder, color: Colors.purple),
              title: const Text('광고보고 파일에 저장'),
              onTap: () {
                Navigator.pop(context);
                _showAdAndSaveToFile(imageData, imageFormat);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.purple),
              title: const Text('광고보고 공유하기'),
              onTap: () {
                Navigator.pop(context);
                _showAdAndShareImage(imageData, imageFormat);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAdAndSaveToGallery(Uint8List imageData, int quality) async {
    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    await AdService.shared.showFullScreenAd(
      onAdDismissed: () {
        // 로딩 다이얼로그 닫기
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        _saveToGallery(imageData, quality);
      },
      onAdFailedToShow: () {
        // 로딩 다이얼로그 닫기
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        // 광고 실패 시에도 저장 진행
        _saveToGallery(imageData, quality);
      },
    );
  }

  Future<void> _showAdAndSaveToFile(
      Uint8List imageData, String imageFormat) async {
    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    await AdService.shared.showFullScreenAd(
      onAdDismissed: () {
        // 로딩 다이얼로그 닫기
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        _saveToFile(imageData, imageFormat);
      },
      onAdFailedToShow: () {
        // 로딩 다이얼로그 닫기
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        // 광고 실패 시에도 저장 진행
        _saveToFile(imageData, imageFormat);
      },
    );
  }

  Future<void> _showAdAndShareImage(
      Uint8List imageData, String imageFormat) async {
    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    await AdService.shared.showFullScreenAd(
      onAdDismissed: () {
        // 로딩 다이얼로그 닫기
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        _shareImage(imageData, imageFormat);
      },
      onAdFailedToShow: () {
        // 로딩 다이얼로그 닫기
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        // 광고 실패 시에도 공유 진행
        _shareImage(imageData, imageFormat);
      },
    );
  }

  Future<void> _saveToGallery(Uint8List imageData, int quality) async {
    try {
      await ImageGallerySaver.saveImage(
        imageData,
        quality: quality,
        name: 'frame_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('앨범에 저장되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('앨범 저장 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveToFile(Uint8List imageData, String imageFormat) async {
    try {
      print(
          'DEBUG: _saveToFile 시작 - 플랫폼: ${Platform.operatingSystem}, 이미지 포맷: $imageFormat');
      if (Platform.isMacOS) {
        print('DEBUG: macOS 파일 저장 시작');
        final defaultFileName =
            'frame_${_currentPosition.inSeconds}s_${DateTime.now().millisecondsSinceEpoch}.${imageFormat.toLowerCase()}';
        print('DEBUG: 파일명: $defaultFileName');
        final MacosFilePicker picker = MacosFilePicker();
        print('DEBUG: MacosFilePicker.pick 호출 시작');
        final result = await picker.pick(
          MacosFilePickerMode.saveFile,
          defaultName: defaultFileName,
          allowedFileExtensions: [imageFormat.toLowerCase()],
        );

        print(
            'DEBUG: macOS 파일 선택 완료, result: ${result?.map((e) => e.path).toList()}');
        if (result == null || result.isEmpty) {
          print('DEBUG: 사용자가 저장 취소');
          return;
        }

        final filePath = result.first.path;
        print('DEBUG: 선택한 파일 경로: $filePath');
        final file = File(filePath);
        try {
          await file.writeAsBytes(imageData);
          print('DEBUG: 파일 저장 완료, 크기: ${imageData.length} bytes');
        } catch (e, stackTrace) {
          print('ERROR: 파일 쓰기 실패');
          print('ERROR: 에러 메시지: $e');
          print('ERROR: 스택 트레이스: $stackTrace');
          rethrow;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('파일 저장 완료: ${path.basename(filePath)}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (Platform.isIOS) {
        // iOS에서는 네이티브 UIDocumentPickerViewController 사용
        print('DEBUG: iOS 파일 저장 시작');
        final fileName =
            'frame_${_currentPosition.inSeconds}s_${DateTime.now().millisecondsSinceEpoch}.${imageFormat.toLowerCase()}';
        print('DEBUG: 파일명: $fileName');

        // 임시 파일 생성
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/$fileName');
        print('DEBUG: 임시 파일 경로: ${tempFile.path}');
        await tempFile.writeAsBytes(imageData);
        print('DEBUG: 임시 파일 생성 완료, 크기: ${imageData.length} bytes');

        // 네이티브 MethodChannel을 사용해서 파일 저장 다이얼로그 열기
        print('DEBUG: _fileSaveChannel.invokeMethod 호출 시작');
        String? outputFile;
        try {
          final result = await _fileSaveChannel.invokeMethod('saveFile', {
            'filePath': tempFile.path,
            'fileName': fileName,
          });
          outputFile = result as String?;
          print(
              'DEBUG: _fileSaveChannel.invokeMethod 완료, outputFile: $outputFile');
        } catch (e, stackTrace) {
          print('ERROR: _fileSaveChannel.invokeMethod 실패');
          print('ERROR: 에러 메시지: $e');
          print('ERROR: 스택 트레이스: $stackTrace');
          rethrow;
        }

        if (outputFile != null && outputFile.isNotEmpty) {
          print('DEBUG: 파일 저장 완료: $outputFile');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('파일 저장 완료: ${path.basename(outputFile)}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          print('DEBUG: 사용자가 저장 취소');
        }

        // 임시 파일 삭제
        try {
          await tempFile.delete();
          print('DEBUG: 임시 파일 삭제 완료');
        } catch (e) {
          print('WARNING: 임시 파일 삭제 실패: $e');
        }
      } else {
        // Android에서는 파일 저장 다이얼로그 사용
        print('DEBUG: Android 파일 저장 시작');
        final tempDir = Directory.systemTemp;
        final fileName =
            'frame_${_currentPosition.inSeconds}s_${DateTime.now().millisecondsSinceEpoch}.${imageFormat.toLowerCase()}';
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(imageData);
        print('DEBUG: 임시 파일 생성 완료: ${tempFile.path}');

        // 파일 저장 다이얼로그
        const XTypeGroup imageTypeGroup = XTypeGroup(
          label: 'images',
          extensions: ['png', 'jpg', 'jpeg'],
        );

        print('DEBUG: getSaveLocation 호출 시작');
        final savedFile = await getSaveLocation(
          acceptedTypeGroups: [imageTypeGroup],
          suggestedName: fileName,
        );
        print('DEBUG: getSaveLocation 완료, savedFile: ${savedFile?.path}');

        if (savedFile != null) {
          final savedPath = savedFile.path;
          print('DEBUG: 파일 복사 시작: ${tempFile.path} -> $savedPath');
          await tempFile.copy(savedPath);
          print('DEBUG: 파일 복사 완료');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('파일 저장 완료: ${path.basename(savedPath)}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          print('DEBUG: 사용자가 저장 취소');
        }

        // 임시 파일 삭제
        try {
          await tempFile.delete();
          print('DEBUG: 임시 파일 삭제 완료');
        } catch (e) {
          print('WARNING: 임시 파일 삭제 실패: $e');
        }
      }
      print('DEBUG: _saveToFile 성공 완료');
    } catch (e, stackTrace) {
      print('ERROR: _saveToFile 실패');
      print('ERROR: 에러 메시지: $e');
      print('ERROR: 스택 트레이스: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('파일 저장 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareImage(Uint8List imageData, String imageFormat) async {
    try {
      // 임시 파일 생성
      final tempDir = Directory.systemTemp;
      final fileName =
          'frame_${_currentPosition.inSeconds}s_${DateTime.now().millisecondsSinceEpoch}.${imageFormat.toLowerCase()}';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageData);

      // 공유
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '비디오 프레임',
      );

      // 임시 파일 삭제 (공유 후)
      Future.delayed(const Duration(seconds: 2), () {
        try {
          file.deleteSync();
        } catch (e) {
          // 삭제 실패는 무시
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('공유 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveFrame() async {
    if (!_isInitialized) {
      print('ERROR: 비디오가 초기화되지 않았습니다');
      return;
    }

    print('DEBUG: ===== 프레임 저장 시작 =====');
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final imageFormat = prefs.getString('image_format') ?? 'JPEG';
      final quality = prefs.getInt('image_quality') ?? 95;

      Uint8List? uint8list;

      if (Platform.isMacOS) {
        if (_controller == null) {
          throw Exception('Video controller not initialized');
        }

        if (_isPlaying) {
          await _controller!.pause();
        }

        // 화면에 표시된 정확한 위치 사용 (_currentPosition)
        // seek 후 바로 저장할 경우를 위해 약간의 딜레이 후 최신 위치 확인
        await Future.delayed(const Duration(milliseconds: 150));

        // 화면에 표시된 위치를 우선 사용 (사용자가 보는 프레임과 일치)
        var currentPosition = _currentPosition;

        // 마지막 프레임 근처일 때 약간 앞으로 이동 (비디오 끝은 프레임이 없을 수 있음)
        if (currentPosition >=
            _totalDuration - const Duration(milliseconds: 100)) {
          currentPosition = _totalDuration - const Duration(milliseconds: 100);
          print('DEBUG: 마지막 프레임 근처이므로 위치 조정: ${currentPosition.inSeconds}초');
        }

        // 비디오 길이를 초과하지 않도록 보장
        currentPosition =
            currentPosition > _totalDuration ? _totalDuration : currentPosition;
        currentPosition =
            currentPosition < Duration.zero ? Duration.zero : currentPosition;

        final positionInSeconds = currentPosition.inMilliseconds / 1000.0;

        print(
            'DEBUG: 저장할 프레임 위치: ${currentPosition.inSeconds}초 (${currentPosition.inMilliseconds}ms)');
        print(
            'DEBUG: 비디오 총 길이: ${_totalDuration.inSeconds}초 (${_totalDuration.inMilliseconds}ms)');

        try {
          final String? framePath =
              await _channel.invokeMethod('extractFrame', {
            'videoPath': widget.videoPath,
            'positionInSeconds': positionInSeconds,
          });

          if (framePath != null) {
            final file = File(framePath);
            if (await file.exists()) {
              uint8list = await file.readAsBytes();
              await file.delete();
            } else {
              throw Exception('Extracted frame file not found');
            }
          } else {
            throw Exception('Frame path is null');
          }
        } catch (e) {
          print('ERROR: 네이티브 extractFrame 에러: $e');
          rethrow;
        }
      } else {
        // iOS/Android에서도 마지막 프레임 체크
        var savePosition = _currentPosition;
        if (savePosition >=
            _totalDuration - const Duration(milliseconds: 100)) {
          savePosition = _totalDuration - const Duration(milliseconds: 100);
          print('DEBUG: 마지막 프레임 근처이므로 위치 조정: ${savePosition.inSeconds}초');
        }
        savePosition =
            savePosition > _totalDuration ? _totalDuration : savePosition;
        savePosition =
            savePosition < Duration.zero ? Duration.zero : savePosition;

        uint8list = await VideoThumbnail.thumbnailData(
          video: widget.videoPath,
          timeMs: savePosition.inMilliseconds
              .clamp(0, _totalDuration.inMilliseconds),
          imageFormat: ImageFormat.PNG,
          quality: 100,
        );
      }

      if (uint8list != null) {
        // 설정에 따라 이미지 포맷 변환 및 quality 적용
        uint8list = await _convertImageFormat(uint8list, imageFormat, quality);

        // 저장 방법 선택 다이얼로그 표시
        if (mounted) {
          setState(() => _isSaving = false);
          _showSaveOptionsDialog(uint8list, imageFormat, quality);
        }
      } else {
        throw Exception('Failed to extract frame');
      }
    } catch (e) {
      print('ERROR: 프레임 저장 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving frame: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<Uint8List> _convertImageFormat(
      Uint8List imageData, String imageFormat, int quality) async {
    try {
      // PNG로 디코딩
      final decodedImage = img.decodeImage(imageData);
      if (decodedImage == null) {
        print('WARNING: 이미지 디코딩 실패, 원본 반환');
        return imageData;
      }

      Uint8List convertedData;

      switch (imageFormat.toUpperCase()) {
        case 'JPEG':
        case 'JPG':
          // JPEG로 변환
          final jpegData = img.encodeJpg(decodedImage, quality: quality);
          convertedData = Uint8List.fromList(jpegData);
          break;
        case 'HEIF':
          // HEIF는 flutter_image_compress 사용
          final tempDir = Directory.systemTemp;
          final tempFile = File(
              '${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.png');
          await tempFile.writeAsBytes(imageData);

          final result = await FlutterImageCompress.compressWithFile(
            tempFile.absolute.path,
            quality: quality,
            format: CompressFormat.heic,
          );

          await tempFile.delete();

          if (result != null) {
            convertedData = result;
          } else {
            print('WARNING: HEIF 변환 실패, PNG로 대체');
            convertedData = imageData;
          }
          break;
        case 'PNG':
        default:
          // PNG는 quality가 적용되지 않지만, flutter_image_compress로 압축 가능
          if (quality < 100) {
            final tempDir = Directory.systemTemp;
            final tempFile = File(
                '${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.png');
            await tempFile.writeAsBytes(imageData);

            final result = await FlutterImageCompress.compressWithFile(
              tempFile.absolute.path,
              quality: quality,
              format: CompressFormat.png,
            );

            await tempFile.delete();

            if (result != null) {
              convertedData = result;
            } else {
              convertedData = imageData;
            }
          } else {
            convertedData = imageData;
          }
          break;
      }

      return convertedData;
    } catch (e) {
      print('ERROR: 이미지 포맷 변환 실패: $e');
      return imageData; // 변환 실패 시 원본 반환
    }
  }

  void _seekToPosition(Duration position) {
    _controller?.seekTo(position);
    // seek 후 즉시 상태 업데이트
    setState(() {
      _currentPosition = position;
    });
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
  }

  void _seekFrame(bool forward) {
    if (_controller == null || _totalDuration == Duration.zero) return;
    // 0.01초씩 이동
    final seekDuration = const Duration(milliseconds: 10);
    final newPosition = forward
        ? _currentPosition + seekDuration
        : _currentPosition - seekDuration;

    final clampedPosition = newPosition < Duration.zero
        ? Duration.zero
        : (newPosition > _totalDuration ? _totalDuration : newPosition);

    _seekToPosition(clampedPosition);
  }

  void _startContinuousSeek(bool forward) {
    if (_controller == null || _totalDuration == Duration.zero) return;
    _isContinuousSeeking = true;
    _continuousSeekLoop(forward);
  }

  void _continuousSeekLoop(bool forward) async {
    while (_isContinuousSeeking &&
        _controller != null &&
        _totalDuration != Duration.zero) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_isContinuousSeeking ||
          _controller == null ||
          _totalDuration == Duration.zero) break;

      // 0.5초마다 0.01초씩 이동
      final seekDuration = const Duration(milliseconds: 10);
      final newPosition = forward
          ? _currentPosition + seekDuration
          : _currentPosition - seekDuration;

      final clampedPosition = newPosition < Duration.zero
          ? Duration.zero
          : (newPosition > _totalDuration ? _totalDuration : newPosition);

      _seekToPosition(clampedPosition);
    }
  }

  void _stopContinuousSeek() {
    _isContinuousSeeking = false;
  }

  void _showPlaybackSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scrubbing and Playback Speed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSpeedOption('Snail', 0.01, '01'),
            _buildSpeedOption('0.1x', 0.1, '10'),
            _buildSpeedOption('0.25x', 0.25, '25'),
            _buildSpeedOption('0.5x', 0.5, '50'),
            _buildSpeedOption('1.0x', 1.0, '100'),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedOption(String label, double speed, String number) {
    final isSelected = (_playbackSpeed - speed).abs() < 0.001; // 부동소수점 비교

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? Colors.purple : Colors.grey[300],
        ),
        child: Center(
          child: Text(
            number,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing:
          isSelected ? const Icon(Icons.check, color: Colors.purple) : null,
      onTap: () {
        setState(() {
          _playbackSpeed = speed;
        });
        _controller?.setPlaybackSpeed(speed);
        Navigator.pop(context);
      },
    );
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final milliseconds = duration.inMilliseconds.remainder(1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(2, '0')}';
  }

  Widget _buildTimelineWithThumbnails() {
    return SizedBox(
      height: 80,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final timelineWidth = constraints.maxWidth;
          final thumbnailWidth = 60.0;
          final thumbnailHeight = 60.0;

          return GestureDetector(
            onHorizontalDragStart: (details) {
              _onTimelineDragStart(details, timelineWidth);
            },
            onHorizontalDragUpdate: (details) {
              _onTimelineDragUpdate(details, timelineWidth);
            },
            onHorizontalDragEnd: (_) {
              // 드래그 종료 시 처리 (필요시)
            },
            onTapDown: (details) {
              _onTimelineTap(details, timelineWidth);
            },
            child: Stack(
              clipBehavior: Clip.none, // 인디케이터가 Stack 밖으로 나가도 보이도록
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      // 타임라인 전체 배경
                      Container(
                        height: thumbnailHeight,
                        width: timelineWidth,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                        ),
                      ),
                      // 썸네일들
                      ...List.generate(_thumbnailImages.length, (index) {
                        final image = _thumbnailImages[index];
                        // 썸네일을 타임라인 전체에 균등하게 배치
                        // 첫 번째와 마지막 썸네일도 타임라인 안에 포함되도록
                        // 0부터 1까지 균등 분배 (첫 번째: 0에 가깝게, 마지막: 1에 가깝게)
                        final ratio = index /
                            (_thumbnailImages.length - 1)
                                .clamp(1, double.infinity);
                        // 썸네일이 타임라인 밖으로 나가지 않도록 계산
                        // 첫 번째는 왼쪽 끝에서 약간 안쪽, 마지막은 오른쪽 끝에서 약간 안쪽
                        final availableWidth = timelineWidth - thumbnailWidth;
                        final left =
                            (availableWidth * ratio).clamp(0.0, availableWidth);

                        return Positioned(
                          left: left,
                          top: 0, // 썸네일을 타임라인 상단에 배치
                          child: GestureDetector(
                            onTap: () {
                              final position = Duration(
                                milliseconds:
                                    (_totalDuration.inMilliseconds * ratio)
                                        .round(),
                              );
                              _seekToPosition(position);
                            },
                            child: Container(
                              width: thumbnailWidth,
                              height: thumbnailHeight,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: image != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: RawImage(
                                        image: image,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.image,
                                          color: Colors.grey),
                                    ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                // 현재 위치 인디케이터 (썸네일 위아래로 동일한 길이만큼 확장)
                if (_totalDuration != Duration.zero &&
                    _currentPosition != Duration.zero)
                  Positioned(
                    left: (_currentPosition.inMilliseconds /
                            _totalDuration.inMilliseconds *
                            timelineWidth)
                        .clamp(0.0, timelineWidth - 2),
                    top: -5, // 썸네일 위로 10px 확장
                    child: Container(
                      width: 3, // 두께를 약간 증가
                      height: thumbnailHeight + 10, // 썸네일 높이 + 위아래 각 10px
                      decoration: BoxDecoration(
                        color: Colors.purple[700], // 더 진한 보라색
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: Colors.white,
                            width: 1,
                          ),
                        ), // 상하단에 흰색 테두리 추가
                        boxShadow: [
                          BoxShadow(
                            color: Colors.purple[900]!.withOpacity(0.8),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.5),
                            blurRadius: 2,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _onTimelineDragStart(DragStartDetails details, double timelineWidth) {
    if (_totalDuration == Duration.zero) return;
    final localX = details.localPosition.dx;
    final clampedX = localX.clamp(0.0, timelineWidth);
    final ratio = clampedX / timelineWidth;
    final position = Duration(
      milliseconds:
          (_totalDuration.inMilliseconds * ratio.clamp(0.0, 1.0)).round(),
    );
    _seekToPosition(position);
  }

  void _onTimelineDragUpdate(DragUpdateDetails details, double timelineWidth) {
    if (_totalDuration == Duration.zero) return;
    final localX = details.localPosition.dx;
    final clampedX = localX.clamp(0.0, timelineWidth);
    final ratio = clampedX / timelineWidth;
    final position = Duration(
      milliseconds:
          (_totalDuration.inMilliseconds * ratio.clamp(0.0, 1.0)).round(),
    );
    setState(() {
      _currentPosition = position;
    });
    _seekToPosition(position);
  }

  void _onTimelineTap(TapDownDetails details, double timelineWidth) {
    if (_totalDuration == Duration.zero) return;
    final localX = details.localPosition.dx;
    final clampedX = localX.clamp(0.0, timelineWidth);
    final ratio = clampedX / timelineWidth;
    final position = Duration(
      milliseconds:
          (_totalDuration.inMilliseconds * ratio.clamp(0.0, 1.0)).round(),
    );
    _seekToPosition(position);
  }

  @override
  void dispose() {
    _controller?.dispose();
    for (var image in _thumbnailImages) {
      image?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.purple),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Choose Frame',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.purple),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    videoPath: widget.videoPath,
                    videoDuration: _totalDuration,
                    videoWidth: _videoWidth,
                    videoHeight: _videoHeight,
                    frameRate: _frameRate,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isInitialized || _hasError
          ? _buildVideoPlayer()
          : _buildLoadingView(),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.purple),
    );
  }

  Widget _buildVideoPlayer() {
    // 에러가 있거나 컨트롤러가 없을 때 기본 aspect ratio 사용
    final aspectRatio = _controller != null && !_hasError
        ? _controller!.value.aspectRatio
        : 16 / 9; // 기본 비율

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _hasError ? null : _togglePlayPause,
            child: Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 비디오 또는 검은 배경
                    if (_controller != null && !_hasError)
                      VideoPlayer(_controller!)
                    else
                      Container(
                        color: Colors.black,
                        child: _hasError
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    size: 48,
                                    color: Colors.white54,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    '비디오를 로드할 수 없습니다',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _hasError = false;
                                        _errorMessage = null;
                                        _isInitialized = false;
                                      });
                                      _initializeVideo();
                                    },
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('다시 시도'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.purple,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.purple),
                              ),
                      ),
                    // 재생 버튼 (에러가 없고 일시정지 상태일 때만)
                    if (!_hasError && _controller != null && !_isPlaying)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(12),
                        child: const Icon(
                          Icons.play_arrow,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildControls(),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
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
          Text(
            _formatTime(_currentPosition),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          // 타임라인 with 썸네일
          if (_isLoadingThumbnails)
            const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_thumbnailImages.isNotEmpty &&
              _totalDuration != Duration.zero)
            _buildTimelineWithThumbnails(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                ),
                iconSize: 32,
                onPressed: _togglePlayPause,
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => _seekFrame(false),
                onLongPressStart: (_) {
                  _isContinuousSeeking = true;
                  _startContinuousSeek(false);
                },
                onLongPressEnd: (_) {
                  _stopContinuousSeek();
                },
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  iconSize: 28,
                  onPressed: () => _seekFrame(false),
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => _seekFrame(true),
                onLongPressStart: (_) {
                  _isContinuousSeeking = true;
                  _startContinuousSeek(true);
                },
                onLongPressEnd: (_) {
                  _stopContinuousSeek();
                },
                child: IconButton(
                  icon: const Icon(Icons.arrow_forward, color: Colors.black),
                  iconSize: 28,
                  onPressed: () => _seekFrame(true),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.speed, color: Colors.black),
                iconSize: 28,
                onPressed: _showPlaybackSpeedDialog,
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download, color: Colors.purple),
                iconSize: 32,
                onPressed: _isSaving ? null : _saveFrame,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
