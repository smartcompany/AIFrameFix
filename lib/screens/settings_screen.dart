import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  final String? videoPath;
  final Duration? videoDuration;
  final int? videoWidth;
  final int? videoHeight;
  final double? frameRate;

  const SettingsScreen({
    super.key,
    this.videoPath,
    this.videoDuration,
    this.videoWidth,
    this.videoHeight,
    this.frameRate,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _imageFormat = 'JPEG';
  int _quality = 95;
  bool _includeMetadata = true;
  String _timeFormat = 'Frames';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _imageFormat = prefs.getString('image_format') ?? 'JPEG';
      _quality = prefs.getInt('image_quality') ?? 95;
      _includeMetadata = prefs.getBool('include_metadata') ?? true;
      _timeFormat = prefs.getString('time_format') ?? 'Frames';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('image_format', _imageFormat);
    await prefs.setInt('image_quality', _quality);
    await prefs.setBool('include_metadata', _includeMetadata);
    await prefs.setString('time_format', _timeFormat);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () {
            _saveSettings();
            Navigator.pop(context);
          },
        ),
        title: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.purple,
          tabs: const [
            Tab(text: 'Settings'),
            Tab(text: 'Metadata'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSettingsTab(),
          _buildMetadataTab(),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSection(
          title: 'IMAGE FORMAT',
          children: [
            _buildSegmentedControl(
              options: const ['JPEG', 'PNG', 'HEIF'],
              selected: _imageFormat,
              onChanged: (value) {
                setState(() => _imageFormat = value);
                _saveSettings();
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Quality',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        if (_quality > 1) {
                          setState(() => _quality -= 5);
                          _saveSettings();
                        }
                      },
                    ),
                    Text(
                      '$_quality%',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () {
                        if (_quality < 100) {
                          setState(() => _quality += 5);
                          _saveSettings();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'A smaller compression quality results in a smaller file size with a slightly degraded photo quality.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          title: 'Metadata',
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Adds creation date, GPS location and other metadata to exported images, if available.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
                Switch(
                  value: _includeMetadata,
                  onChanged: (value) {
                    setState(() => _includeMetadata = value);
                    _saveSettings();
                  },
                  activeColor: Colors.purple,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          title: 'EDITOR',
          children: [
            ListTile(
              title: const Text('Time Format'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeFormat,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              onTap: () {
                _showTimeFormatDialog();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetadataTab() {
    if (widget.videoPath == null) {
      return const Center(
        child: Text('No video loaded'),
      );
    }

    final file = File(widget.videoPath!);
    final fileSize = file.existsSync() ? file.lengthSync() : 0;
    final fileSizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildMetadataItem('Type', 'Video'),
        _buildMetadataItem(
          'Created',
          widget.videoPath != null
              ? 'Today at ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}'
              : 'Unknown',
        ),
        _buildMetadataItem(
          'Dimensions',
          widget.videoWidth != null && widget.videoHeight != null
              ? '${widget.videoWidth} x ${widget.videoHeight} px'
              : 'Unknown',
        ),
        _buildMetadataItem(
          'Duration',
          widget.videoDuration != null
              ? _formatDuration(widget.videoDuration!)
              : 'Unknown',
        ),
        _buildMetadataItem(
          'FrameRate',
          widget.frameRate != null
              ? '${widget.frameRate!.toStringAsFixed(0)} fps'
              : 'Unknown',
        ),
        _buildMetadataItem('Kind', 'MPEG-4 Movie'),
        _buildMetadataItem('Codec', 'H.264'),
        _buildMetadataItem('Size', '$fileSizeMB MB'),
        _buildMetadataItem('Software', 'Lavf60.16.100'),
      ],
    );
  }

  Widget _buildMetadataItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[600],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSegmentedControl({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: options.map((option) {
          final isSelected = option == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(option),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.purple : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  option,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }


  void _showTimeFormatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Time Format'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Frames'),
              onTap: () {
                setState(() => _timeFormat = 'Frames');
                _saveSettings();
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Time'),
              onTap: () {
                setState(() => _timeFormat = 'Time');
                _saveSettings();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

