import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../services/app_state_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> with SingleTickerProviderStateMixin {
  final _commentController = TextEditingController();
  final List<String> _categories = [
    'App Performance',
    'Map Accuracy',
    'Feature Suggestion',
    'Report a Bug',
    'General Feedback'
  ];
  String? _selectedCategory;
  int _selectedRating = 0;
  bool _allowFollowUp = true;
  bool _isSubmitting = false;
  File? _selectedImage;

  late AnimationController _toastController;
  late Animation<double> _toastAnimation;

  @override
  void initState() {
    super.initState();
    _toastController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _toastAnimation = CurvedAnimation(
      parent: _toastController,
      curve: Curves.easeOutBack,
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _toastController.dispose();
    super.dispose();
  }

  void _submitFeedback() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category.')),
      );
      return;
    }
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    String? imageUrl;

    try {
      if (_selectedImage != null) {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('feedbacks/screenshots/${DateTime.now().microsecondsSinceEpoch}_${FirebaseAuth.instance.currentUser?.uid ?? "anon"}.jpg');
          
          await storageRef.putFile(_selectedImage!);
          imageUrl = await storageRef.getDownloadURL();
        } catch (storageError) {
          debugPrint('Storage upload failed: $storageError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Couldn't attach screenshot — submitting feedback without it")),
            );
          }
        }
      }

      final data = {
        'category': _selectedCategory,
        'rating': _selectedRating,
        'comments': _commentController.text.trim(),
        'hasAttachment': imageUrl != null,
        'allowFollowUp': FirebaseAuth.instance.currentUser != null ? _allowFollowUp : false,
        'timestamp': FieldValue.serverTimestamp(),
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'imageUrl': imageUrl,
        'status': 'new',
      };

      await AppStateService.instance.submitFeedback(data);

      if (mounted) {
        _toastController.forward();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _toastController.reverse().then((_) {
              if (mounted) Navigator.pop(context);
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error submitting feedback: $e');
      try {
        FirebaseFirestore.instance.collection('error_logs').add({
          'type': 'feedback_submission_error',
          'error': e.toString(),
          'timestamp': FieldValue.serverTimestamp(),
          'uid': FirebaseAuth.instance.currentUser?.uid,
        });
      } catch (_) {} // Ignore logging errors
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't submit feedback. Please check your connection and try again.")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildIntro(),
                      const SizedBox(height: 32),
                      _buildCategorySelector(),
                      const SizedBox(height: 32),
                      _buildRatingScale(),
                      const SizedBox(height: 32),
                      _buildTextArea(),
                      const SizedBox(height: 32),
                      _buildAttachmentField(),
                      const SizedBox(height: 32),
                      _buildFollowUpToggle(),
                      const SizedBox(height: 32),
                      _buildSubmitButton(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _buildSuccessToast(),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.surface.withValues(alpha: 0.8),
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 4,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Feedback & Suggestions',
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: AppColors.onSurface,
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Help us make SafePaths better for everyone in Marulas.',
          style: GoogleFonts.manrope(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your suggestions directly impact how we improve road safety and flood alerts. Every detail counts toward a more resilient community.',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 16),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.onSurface,
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Select a Category'),
        Wrap(
          spacing: 8,
          runSpacing: 12,
          children: _categories.map((category) {
            final isSelected = _selectedCategory == category;
            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : AppColors.outlineVariant.withValues(alpha: 0.3),
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))]
                      : [],
                ),
                child: Text(
                  category,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRatingScale() {
    final emojis = ['😠', '🙁', '😐', '🙂', '🤩'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Overall Experience'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(5, (index) {
              final rating = index + 1;
              final isSelected = _selectedRating == rating;
              return GestureDetector(
                onTap: () => setState(() => _selectedRating = rating),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Opacity(
                    opacity: isSelected ? 1.0 : 0.4,
                    child: Text(
                      emojis[index],
                      style: const TextStyle(
                        fontSize: 32,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTextArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('How can we improve?'),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: TextField(
            controller: _commentController,
            maxLines: 6,
            style: GoogleFonts.inter(fontSize: 16, color: AppColors.onSurface),
            decoration: InputDecoration(
              hintText: "Tell us what's on your mind...",
              hintStyle: GoogleFonts.inter(color: AppColors.onSurfaceVariant.withValues(alpha: 0.4)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Optional: Add a screenshot or image'),
        if (_selectedImage != null)
          Stack(
            children: [
              Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.file(
                    _selectedImage!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(child: Icon(Icons.broken_image, size: 48, color: AppColors.outline));
                    },
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => setState(() => _selectedImage = null),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          )
        else
          GestureDetector(
            onTap: () async {
              final ImagePicker picker = ImagePicker();
              final XFile? image = await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 70,
              );
              if (image != null) {
                setState(() => _selectedImage = File(image.path));
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No image selected.')),
                  );
                }
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.3),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_a_photo, size: 32, color: AppColors.primaryContainer),
                  const SizedBox(height: 12),
                  Text(
                    'Tap to upload files',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Supports PNG, JPG (Max 5MB)',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.outline.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFollowUpToggle() {
    if (FirebaseAuth.instance.currentUser == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allow Follow-up',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'We may contact you for more details.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _allowFollowUp,
            onChanged: (val) => setState(() => _allowFollowUp = val),
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitFeedback,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 8,
          shadowColor: AppColors.primary.withValues(alpha: 0.5),
        ),
        child: _isSubmitting
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2),
              )
            : Text(
                'Submit Feedback',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildSuccessToast() {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: ScaleTransition(
        scale: _toastAnimation,
        child: FadeTransition(
          opacity: _toastAnimation,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Feedback Received!',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSecondary,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Thank you for helping us keep Marulas safe.',
                        style: GoogleFonts.inter(
                          color: AppColors.onSecondary.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
