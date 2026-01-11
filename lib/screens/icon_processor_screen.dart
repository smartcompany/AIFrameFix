import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:macos_file_picker/macos_file_picker.dart';
import 'package:image/image.dart' as img;

class IconProcessorScreen extends StatefulWidget {
  const IconProcessorScreen({super.key});

  @override
  State<IconProcessorScreen> createState() => _IconProcessorScreenState();
}

class _IconProcessorScreenState extends State<IconProcessorScreen> {
  bool _isProcessing = false;
  String? _selectedImagePath;
  String? _processedImagePath;

  Future<void> _pickImage() async {
    try {
      setState(() {
        _selectedImagePath = null;
        _processedImagePath = null;
      });

      const XTypeGroup imageTypeGroup = XTypeGroup(
        label: 'images',
        extensions: ['png', 'jpg', 'jpeg'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: [imageTypeGroup],
      );

      if (file != null && mounted) {
        setState(() {
          _selectedImagePath = file.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _processImage() async {
    if (_selectedImagePath == null) return;

    setState(() => _isProcessing = true);

    try {
      // 이미지 파일 읽기
      final file = File(_selectedImagePath!);
      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // 이미지에서 실제 콘텐츠 영역 찾기 (투명/흰색 제거)
      final processedImage = _removeBorders(image);

      // PNG로 인코딩
      final pngBytes = Uint8List.fromList(img.encodePng(processedImage));

      // 저장할 위치 선택
      final defaultFileName =
          'icon_processed_${DateTime.now().millisecondsSinceEpoch}.png';
      final MacosFilePicker picker = MacosFilePicker();
      final result = await picker.pick(
        MacosFilePickerMode.saveFile,
        defaultName: defaultFileName,
        allowedFileExtensions: ['png'],
      );

      if (result != null && result.isNotEmpty) {
        final savedPath = result.first.path;
        final savedFile = File(savedPath);
        await savedFile.writeAsBytes(pngBytes);

        setState(() {
          _processedImagePath = savedPath;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Image processed and saved successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  img.Image _removeBorders(img.Image image) {
    int left = 0;
    int top = 0;
    int right = image.width;
    int bottom = image.height;

    // 위쪽에서 실제 콘텐츠 시작점 찾기
    for (int y = 0; y < image.height; y++) {
      bool hasContent = false;
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        if (!_isTransparentOrWhite(pixel)) {
          hasContent = true;
          break;
        }
      }
      if (hasContent) {
        top = y;
        break;
      }
    }

    // 아래쪽에서 실제 콘텐츠 끝점 찾기
    for (int y = image.height - 1; y >= 0; y--) {
      bool hasContent = false;
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        if (!_isTransparentOrWhite(pixel)) {
          hasContent = true;
          break;
        }
      }
      if (hasContent) {
        bottom = y + 1;
        break;
      }
    }

    // 왼쪽에서 실제 콘텐츠 시작점 찾기
    for (int x = 0; x < image.width; x++) {
      bool hasContent = false;
      for (int y = top; y < bottom; y++) {
        final pixel = image.getPixel(x, y);
        if (!_isTransparentOrWhite(pixel)) {
          hasContent = true;
          break;
        }
      }
      if (hasContent) {
        left = x;
        break;
      }
    }

    // 오른쪽에서 실제 콘텐츠 끝점 찾기
    for (int x = image.width - 1; x >= 0; x--) {
      bool hasContent = false;
      for (int y = top; y < bottom; y++) {
        final pixel = image.getPixel(x, y);
        if (!_isTransparentOrWhite(pixel)) {
          hasContent = true;
          break;
        }
      }
      if (hasContent) {
        right = x + 1;
        break;
      }
    }

    // 실제 콘텐츠 영역만 crop
    return img.copyCrop(
      image,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  bool _isTransparentOrWhite(img.Pixel pixel) {
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    final a = pixel.a.toInt();

    // 투명한 경우
    if (a < 10) return true;

    // 흰색에 가까운 경우 (RGB 모두 240 이상)
    if (r >= 240 && g >= 240 && b >= 240) return true;

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Icon Processor'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Remove Rounded Corners & White Border',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select an icon image to remove rounded corners and white borders',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_selectedImagePath != null) ...[
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(
                      maxHeight: 300, maxWidth: double.infinity),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_selectedImagePath!),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton.icon(
                onPressed: _selectedImagePath != null && !_isProcessing
                    ? _processImage
                    : null,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image),
                label: Text(_isProcessing
                    ? 'Processing...'
                    : _selectedImagePath != null
                        ? 'Process Image'
                        : 'Select Image First'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isProcessing ? null : _pickImage,
                icon: const Icon(Icons.folder_open),
                label: const Text('Select Icon Image'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_processedImagePath != null) ...[
                const SizedBox(height: 24),
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Image Processed Successfully!',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Saved to: $_processedImagePath',
                          style: TextStyle(color: Colors.green[700]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
