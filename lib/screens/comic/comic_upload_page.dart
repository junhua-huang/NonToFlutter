import 'dart:typed_data';

import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/comic_event.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/comic_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// 发布/编辑漫展页面 — 风格与 CreatePostScreen 统一
class ComicUploadPage extends StatefulWidget {
  final int? eventId;
  const ComicUploadPage({super.key, this.eventId});

  @override
  State<ComicUploadPage> createState() => _ComicUploadPageState();
}

class _ComicUploadPageState extends State<ComicUploadPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _venueController = TextEditingController();
  final _introController = TextEditingController();
  final _websiteController = TextEditingController();
  final _ticketController = TextEditingController();
  final _service = ComicService();
  final ImagePicker _picker = ImagePicker();

  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  int? _selectedCityId;
  String? _selectedCity;
  List<String> _selectedTags = [];
  List<ComicCity> _cities = [];
  final List<XFile> _imageFiles = [];
  final List<Uint8List> _imageBytes = [];
  bool _isSubmitting = false;
  bool _isLoading = false;
  ComicEvent? _editingEvent;

  final List<Map<String, dynamic>> _tagOptions = [
    {'name': '同人志', 'icon': Icons.menu_book_outlined},
    {'name': '官方展', 'icon': Icons.verified_outlined},
    {'name': 'Only', 'icon': Icons.star_outline},
    {'name': '大型展', 'icon': Icons.groups_outlined},
    {'name': '小型展', 'icon': Icons.group_outlined},
    {'name': '动漫', 'icon': Icons.animation_outlined},
    {'name': '游戏', 'icon': Icons.sports_esports_outlined},
    {'name': '周边', 'icon': Icons.shopping_bag_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _loadCities();
    if (widget.eventId != null) {
      _loadEventForEdit();
    }
  }

  Future<void> _loadCities() async {
    try {
      final resp = await _service.getCities();
      if (resp.success && resp.data != null && mounted) {
        setState(() => _cities = resp.data as List<ComicCity>);
      }
    } catch (_) {}
  }

  Future<void> _loadEventForEdit() async {
    setState(() => _isLoading = true);
    try {
      final resp = await _service.getEventDetail(widget.eventId!);
      if (resp.success && resp.data != null && mounted) {
        final e = resp.data as ComicEvent;
        setState(() {
          _editingEvent = e;
          _nameController.text = e.name;
          _venueController.text = e.venue;
          _introController.text = e.intro ?? '';
          _websiteController.text = e.website ?? '';
          _ticketController.text = e.ticketInfo ?? '';
          _selectedCityId = e.cityId;
          _selectedCity = e.cityName;
          _selectedTags = List<String>.from(e.tags);
          _startDate =
              e.startDate != null ? DateTime.tryParse(e.startDate!) : null;
          _endDate = e.endDate != null ? DateTime.tryParse(e.endDate!) : null;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _venueController.dispose();
    _introController.dispose();
    _websiteController.dispose();
    _ticketController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final List<XFile> picked = await _picker.pickMultiImage(
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (picked.isNotEmpty && mounted) {
      final newFiles = picked.toList();
      final newBytes = <Uint8List>[];
      for (final f in newFiles) {
        newBytes.add(await f.readAsBytes());
      }
      setState(() {
        final remaining = 9 - _imageFiles.length;
        if (remaining > 0) {
          _imageFiles.addAll(newFiles.take(remaining));
          _imageBytes.addAll(newBytes.take(remaining));
        }
      });
    }
  }

  Future<List<String>> _uploadImages() async {
    final urls = <String>[];
    for (int i = 0; i < _imageFiles.length; i++) {
      final file = _imageFiles[i];
      try {
        final filename = file.name;
        final ext = filename.contains('.') ? filename.split('.').last : 'jpg';
        final presignResp = await ApiClient().post('/upload/presign', data: {
          'filename': filename,
          'file_type': ext,
          'upload_type': 'comic',
        });
        if (presignResp.statusCode == 200) {
          final data = presignResp.data;
          final putUrl =
              data['presigned_url'] ?? data['put_url'] ?? data['url'];
          final finalUrl =
              data['public_url'] ?? data['file_url'] ?? data['url'];
          await ApiClient().dio.put(putUrl, data: await file.readAsBytes());
          urls.add(finalUrl);
        } else {
          if (mounted) _showSnack('图片 ${i + 1} 上传失败');
        }
      } catch (e) {
        if (mounted) _showSnack('图片 ${i + 1} 上传失败: $e');
      }
    }
    return urls;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCityId == null) {
      _showSnack('请选择城市');
      return;
    }
    if (_startDate == null) {
      _showSnack('请选择开始日期');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      List<String> imageUrls = [];
      if (_imageFiles.isNotEmpty) {
        imageUrls = await _uploadImages();
      }

      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'cityId': _selectedCityId,
        'venue': _venueController.text.trim(),
        'start_date': _startDate != null
            ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
            : null,
        'end_date': _endDate != null
            ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
            : null,
        'start_time': _startTime != null
            ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
            : null,
        'end_time': _endTime != null
            ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}'
            : null,
        'intro': _introController.text.trim(),
        'website': _websiteController.text.trim(),
        'ticket_info': _ticketController.text.trim(),
        'tags': _selectedTags,
        'images': imageUrls,
        'imageUrls': imageUrls,
      };

      ApiResponse resp;
      if (widget.eventId != null && _editingEvent != null) {
        resp = await _service.updateEventData(widget.eventId!, data);
      } else {
        resp = await _service.submitEvent(data);
      }

      if (resp.success && mounted) {
        Navigator.pop(context, true);
      } else if (mounted) {
        _showSnack(resp.message ?? '提交失败');
      }
    } catch (e) {
      if (mounted) _showSnack('提交失败: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              Theme.of(ctx).colorScheme.copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              Theme.of(ctx).colorScheme.copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.eventId != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          isEdit ? '编辑漫展' : '发布漫展',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 0.5, color: AppColors.borderLight),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submit,
            style: TextButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    '发布',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildImageSection(),
                  const SizedBox(height: 20),
                  _buildTextField(
                    controller: _nameController,
                    label: '漫展名称',
                    hint: '输入漫展名称',
                    maxLength: 50,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入漫展名称' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildCityPicker(),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _venueController,
                    label: '场馆',
                    hint: '输入举办场馆',
                    maxLength: 100,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: _buildDateButton(
                              '开始日期', _startDate, _pickStartDate)),
                      const SizedBox(width: 12),
                      Expanded(
                          child:
                              _buildDateButton('结束日期', _endDate, _pickEndDate)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTagSelector(),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _introController,
                    label: '漫展介绍',
                    hint: '介绍一下这个漫展...',
                    maxLines: 5,
                    maxLength: 500,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _websiteController,
                    label: '官网链接（可选）',
                    hint: 'https://...',
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _ticketController,
                    label: '票价信息（可选）',
                    hint: '如：50元/人',
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '封面图片（最多9张，第一张为封面）',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        if (_imageFiles.isNotEmpty)
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _imageFiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_imageBytes[i],
                        width: 100, height: 100, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _imageFiles.removeAt(i);
                        _imageBytes.removeAt(i);
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_imageFiles.isNotEmpty) const SizedBox(height: 8),
        if (_imageFiles.length < 9)
          InkWell(
            onTap: _pickImages,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.borderLight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 32, color: AppColors.textSecondary),
                  const SizedBox(height: 4),
                  Text('添加图片',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          validator: validator,
          style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.backgroundSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            counterText: '',
          ),
        ),
      ],
    );
  }

  Widget _buildCityPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('城市',
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final city = await showModalBottomSheet<ComicCity>(
              context: context,
              backgroundColor: AppColors.background,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.dragHandle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('选择城市',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        children: _cities.map((c) {
                          final isSelected = c.id == _selectedCityId;
                          return ListTile(
                            title: Text(c.name,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                )),
                            trailing: isSelected
                                ? const Icon(Icons.check,
                                    color: AppColors.primary, size: 18)
                                : null,
                            onTap: () => Navigator.pop(ctx, c),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
            if (city != null) {
              setState(() {
                _selectedCityId = city.id;
                _selectedCity = city.name;
              });
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  _selectedCity ?? '请选择城市',
                  style: TextStyle(
                    fontSize: 15,
                    color: _selectedCity != null
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                Icon(Icons.expand_more,
                    size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateButton(String label, DateTime? date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              date != null ? '${date.month}月${date.day}日' : label,
              style: TextStyle(
                fontSize: 14,
                color: date != null
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('标签（可多选）',
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _tagOptions.map((tag) {
            final name = tag['name'] as String;
            final isSelected = _selectedTags.contains(name);
            return FilterChip(
              label: Text(name),
              selected: isSelected,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _selectedTags.add(name);
                  } else {
                    _selectedTags.remove(name);
                  }
                });
              },
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.borderLight,
                ),
              ),
              backgroundColor: AppColors.background,
            );
          }).toList(),
        ),
      ],
    );
  }
}
