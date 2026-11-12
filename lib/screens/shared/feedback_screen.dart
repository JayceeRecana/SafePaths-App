import '../../widgets/report_message_thread.dart';
import '../../widgets/feed_status_notice.dart';
import 'dart:async';
import '../../utils/privacy_diagnostics.dart';
import '../../services/sync_health.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../utils/report_image.dart';
import '../../services/private_media_service.dart';
import '../../services/spark_proof_client.dart';
import '../../widgets/safe_image.dart';
import '../../services/app_state_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/feedback_model.dart';
import '../../config/app_environment.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen>
    with SingleTickerProviderStateMixin {
  final _commentController = TextEditingController();
  final List<String> _categories = [
    'App Performance',
    'Map Accuracy',
    'Feature Suggestion',
    'Report a Bug',
    'General Feedback',
  ];
  String? _selectedCategory;
  int _selectedRating = 0;
  bool _allowFollowUp = false;
  bool _isSubmitting = false;
  Uint8List? _attachment;
  bool _preparing = false, _success = false;
  final _media = PrivateMediaUploader();
  String? _ownerUid;
  StreamSubscription<User?>? _account;
  String? _imageError;
  bool get _busy => _isSubmitting || _preparing || _success;
  bool _sameAccount() =>
      Firebase.apps.isNotEmpty &&
      _ownerUid != null &&
      FirebaseAuth.instance.currentUser?.uid == _ownerUid;
  late AnimationController _toastController;
  late Animation<double> _toastAnimation;

  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      _ownerUid = FirebaseAuth.instance.currentUser?.uid;
      _account = FirebaseAuth.instance.userChanges().listen((user) {
        if (mounted && user?.uid != _ownerUid) {
          _media.dispose();
          setState(() {
            _attachment = null;
            _commentController.clear();
            _selectedRating = 0;
            _imageError =
                'Account changed. Reopen feedback for the signed-in account.';
          });
        }
      });
    }
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
    _media.dispose();
    unawaited(_account?.cancel());
    _commentController.dispose();
    _toastController.dispose();
    super.dispose();
  }

  void _submitFeedback() async {
    if (_busy) return;
    if (_imageError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose another image or explicitly continue without an attachment.',
          ),
        ),
      );
      return;
    }
    if (!_sameAccount()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in with this feedback account.')),
      );
      return;
    }
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Please select a category.'))),
      );
      return;
    }
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Please select a rating.'))),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? imageUrl;
      if (_attachment != null) {
        if (!AppEnvironment.feedbackPhotosEnabled)
          throw StateError('Image attachments are not enabled in this build.');
        imageUrl = await _media.upload('feedback', _ownerUid!, _attachment!);
      }
      if (!_sameAccount()) throw StateError('Account changed.');

      final data = {
        'category': _selectedCategory,
        'rating': _selectedRating,
        'comments': _commentController.text.trim(),
        'hasAttachment': imageUrl != null,
        'allowFollowUp': FirebaseAuth.instance.currentUser != null
            ? _allowFollowUp
            : false,
        'timestamp': FieldValue.serverTimestamp(),
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'imageUrl': imageUrl,
        'status': 'new',
      };

      await AppStateService.instance.submitFeedback(data);

      if (mounted && _sameAccount()) {
        setState(() => _success = true);
        _toastController.forward();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _sameAccount()) {
            _toastController.reverse().then((_) {
              if (mounted && _sameAccount()) Navigator.pop(context);
            });
          }
        });
      }
    } catch (e) {
      if (e is SparkProofException && e.code == 'media-unavailable')
        _media.forget();
      final diagnostic = feedbackFailureDiagnostic(e);
      debugPrint('Feedback submission failed (${diagnostic['errorCode']}).');
      try {
        unawaited(
          FirebaseFirestore.instance
              .collection('error_logs')
              .add({...diagnostic, 'timestamp': FieldValue.serverTimestamp()})
              .timeout(const Duration(seconds: 3))
              .then<void>((_) {}, onError: (Object _) {}),
        );
      } catch (_) {} // Ignore logging errors

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is SparkProofException
                  ? e.message
                  : tr(
                      context,
                      "Couldn't submit feedback. Please check your connection and try again.",
                    ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showFeedbackHistorySheet(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) {
            if (uid == null) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      size: 48,
                      color: AppPalette.of(context).outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'Sign In to View History'),
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        context,
                        'Anonymous submissions cannot be tracked in your personal history.',
                      ),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppPalette.of(context).onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tr(context, 'My Submissions & Responses'),
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.of(context).onSurface,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('feedbacks')
                        .where('userId', isEqualTo: uid)
                        .orderBy('timestamp', descending: true)
                        .snapshots(includeMetadataChanges: true),
                    builder: (context, snapshot) {
                      void retry() {
                        Navigator.of(sheetCtx).pop();
                        _showFeedbackHistorySheet(this.context);
                      }

                      if (snapshot.hasError)
                        return FeedStatusNotice(
                          condition: SyncCondition.failed,
                          isEmpty: true,
                          emptyMessage: '',
                          onRetry: retry,
                        );
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return FeedStatusNotice(
                          condition: SyncCondition.connecting,
                          isEmpty: true,
                          emptyMessage: '',
                          onRetry: retry,
                        );
                      }
                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty &&
                          snapshot.data?.metadata.isFromCache == true) {
                        return FeedStatusNotice(
                          condition: SyncCondition.cached,
                          isEmpty: true,
                          emptyMessage: '',
                          onRetry: retry,
                        );
                      }
                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.rate_review_outlined,
                                  size: 48,
                                  color: AppPalette.of(context).outlineVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  tr(context, 'No feedback history yet'),
                                  style: GoogleFonts.manrope(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppPalette.of(
                                      context,
                                    ).onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  tr(
                                    context,
                                    'Feedback you submit will appear here along with responses from the team.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppPalette.of(
                                      context,
                                    ).onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final data =
                              docs[index].data() as Map<String, dynamic>;
                          final item = FeedbackModel.fromJson(
                            data,
                            docs[index].id,
                          );

                          if (item.userId !=
                              FirebaseAuth.instance.currentUser?.uid)
                            return const SizedBox.shrink();
                          Color statusColor = AppPalette.of(context).secondary;
                          String statusText = 'Submitted';
                          if (item.status == 'reviewed') {
                            statusColor = const Color(0xFF0288D1);
                            statusText = 'Under Review';
                          } else if (item.status == 'resolved') {
                            statusColor = AppPalette.of(context).primary;
                            statusText = data['sparkManaged'] == true
                                ? 'Closed (${data['resolutionOutcome'] ?? 'recorded'})'
                                : 'Resolved';
                          }

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppPalette.of(
                                context,
                              ).surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppPalette.of(
                                  context,
                                ).outlineVariant.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        statusText.toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      DateFormat(
                                        'MMM d, yyyy',
                                      ).format(item.timestamp),
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppPalette.of(
                                          context,
                                        ).onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  item.category,
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppPalette.of(context).onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '"${item.comments}"',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppPalette.of(
                                      context,
                                    ).onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                if (item.imageUrl != null)
                                  SafeImage(
                                    imageUrl: item.imageUrl,
                                    mediaResourceId: item.id,
                                    height: 160,
                                    fit: BoxFit.contain,
                                  ),
                                if (data['hasAdminUpdates'] == true)
                                  ReportMessageThread(
                                    reportId: item.id,
                                    feedback: true,
                                  ),
                                if (data['hasAdminUpdates'] != true &&
                                    item.adminReply != null &&
                                    item.adminReply!.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppPalette.of(
                                        context,
                                      ).primaryContainer.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppPalette.of(
                                          context,
                                        ).primary.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.verified_user_rounded,
                                              size: 14,
                                              color: AppPalette.of(
                                                context,
                                              ).primary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              tr(
                                                context,
                                                'SafePaths Team Response:',
                                              ),
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppPalette.of(
                                                  context,
                                                ).primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.adminReply!,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: AppPalette.of(
                                              context,
                                            ).onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting && !_preparing,
      child: AbsorbPointer(
        absorbing: _busy,
        child: Scaffold(
          backgroundColor: AppPalette.of(context).surface,
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 24.0,
                      ),
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
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppPalette.of(context).surface.withValues(alpha: 0.8),
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 4,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppPalette.of(context).onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        tr(context, 'Feedback & Suggestions'),
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: AppPalette.of(context).onSurface,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.history_rounded),
          tooltip: tr(context, 'My Feedback History'),
          onPressed: () => _showFeedbackHistorySheet(context),
        ),
      ],
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'Help us make SafePaths better for everyone in Marulas.'),
          style: GoogleFonts.manrope(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppPalette.of(context).primary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            context,
            'Your suggestions directly impact how we improve road safety and flood alerts. Every detail counts toward a more resilient community.',
          ),
          style: GoogleFonts.inter(
            fontSize: 16,
            color: AppPalette.of(
              context,
            ).onSurfaceVariant.withValues(alpha: 0.8),
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
          color: AppPalette.of(context).onSurface,
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(tr(context, 'Select a Category')),
        Wrap(
          spacing: 8,
          runSpacing: 12,
          children: _categories.map((category) {
            final isSelected = _selectedCategory == category;
            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppPalette.of(context).primary
                      : AppPalette.of(context).surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Colors.transparent
                        : AppPalette.of(
                            context,
                          ).outlineVariant.withValues(alpha: 0.3),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppPalette.of(
                              context,
                            ).primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  category,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppPalette.of(context).onPrimary
                        : AppPalette.of(context).onSurface,
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
        _buildSectionLabel(tr(context, 'Overall Experience')),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.of(context).surfaceContainerLow,
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
                    color: isSelected
                        ? AppPalette.of(context).primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Opacity(
                    opacity: isSelected ? 1.0 : 0.4,
                    child: Text(
                      emojis[index],
                      style: const TextStyle(fontSize: 32),
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
        _buildSectionLabel(tr(context, 'How can we improve?')),
        Container(
          decoration: BoxDecoration(
            color: AppPalette.of(context).surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: TextField(
            controller: _commentController,
            maxLines: 6,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: AppPalette.of(context).onSurface,
            ),
            decoration: InputDecoration(
              hintText: tr(context, "Tell us what's on your mind..."),
              hintStyle: GoogleFonts.inter(
                color: AppPalette.of(
                  context,
                ).onSurfaceVariant.withValues(alpha: 0.4),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentField() {
    if (!AppEnvironment.feedbackPhotosEnabled)
      return const Text(
        'Screenshot attachments are unavailable in this build.',
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Optional screenshot'),
        if (_attachment != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              _attachment!,
              width: double.infinity,
              height: 160,
              fit: BoxFit.contain,
              cacheWidth: 800,
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _attachment = null;
                    _media.forget();
                    _imageError = null;
                  }),
            child: const Text('Remove attachment'),
          ),
        ],
        if (_preparing) const LinearProgressIndicator(),
        if (_imageError != null) ...[
          Text(_imageError!),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _attachment = null;
                    _media.forget();
                    _imageError = null;
                  }),
            child: const Text('Continue without attachment'),
          ),
        ],
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  if (!_sameAccount()) return;
                  setState(() {
                    _preparing = true;
                    _imageError = null;
                  });
                  try {
                    final image = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1600,
                      maxHeight: 1600,
                      imageQuality: 90,
                    );
                    if (image == null || !_sameAccount()) return;
                    final file = File(image.path);
                    if (await file.length() > maxReportPhotoBytes)
                      throw const FormatException(
                        'Choose an image no larger than 10 MB.',
                      );
                    final prepared = await compute(preparePrivateMedia, {
                      'purpose': 'feedback',
                      'bytes': await file.readAsBytes(),
                    });
                    if (mounted && _sameAccount())
                      setState(() {
                        _attachment = prepared;
                        _media.forget();
                      });
                  } catch (_) {
                    if (mounted)
                      setState(
                        () => _imageError =
                            'This image could not be prepared. Choose another JPG or PNG.',
                      );
                  } finally {
                    if (mounted) setState(() => _preparing = false);
                  }
                },
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _attachment == null
                ? 'Choose screenshot'
                : 'Choose another screenshot',
          ),
        ),
      ],
    );
  }

  Widget _buildFollowUpToggle() {
    if (FirebaseAuth.instance.currentUser == null)
      return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'Allow Follow-up'),
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.of(context).onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr(context, 'We may contact you for more details.'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppPalette.of(
                      context,
                    ).onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _allowFollowUp,
            onChanged: (val) => setState(() => _allowFollowUp = val),
            activeThumbColor: AppPalette.of(context).primary,
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
          backgroundColor: AppPalette.of(context).primary,
          foregroundColor: AppPalette.of(context).onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 8,
          shadowColor: AppPalette.of(context).primary.withValues(alpha: 0.5),
        ),
        child: _isSubmitting
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: AppPalette.of(context).onPrimary,
                  strokeWidth: 2,
                ),
              )
            : Text(
                tr(context, 'Submit Feedback'),
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
              color: AppPalette.of(context).secondary,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppPalette.of(
                    context,
                  ).secondary.withValues(alpha: 0.3),
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
                        tr(context, 'Feedback Received!'),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: AppPalette.of(context).onSecondary,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        tr(
                          context,
                          'Thank you for helping us keep Marulas safe.',
                        ),
                        style: GoogleFonts.inter(
                          color: AppPalette.of(
                            context,
                          ).onSecondary.withValues(alpha: 0.9),
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
