import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../models/feedback_model.dart';

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  String _statusFilter = 'new'; // 'new', 'reviewed', 'resolved'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: 'User Feedback',
        showBackButton: Navigator.canPop(context),
        onBackPressed: Navigator.canPop(context) ? () => Navigator.pop(context) : null,
        showProfile: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'new', label: Text('New')),
                  ButtonSegment(value: 'reviewed', label: Text('Reviewed')),
                  ButtonSegment(value: 'resolved', label: Text('Resolved')),
                ],
                selected: {_statusFilter},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() => _statusFilter = newSelection.first);
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.primaryContainer,
                  selectedForegroundColor: AppColors.primary,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('feedbacks')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading feedback: ${snapshot.error}',
                style: GoogleFonts.inter(color: AppColors.error),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final allDocs = snapshot.data?.docs ?? [];
          final docs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? 'new';
            return status == _statusFilter;
          }).toList();
          
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.feedback_outlined, size: 48, color: AppColors.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'No feedback received yet.',
                    style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final feedback = FeedbackModel.fromJson(data, docs[index].id);

              return _FeedbackCard(feedback: feedback);
            },
          );
        },
      ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final FeedbackModel feedback;

  const _FeedbackCard({required this.feedback});

  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) return 'JUST NOW';
    if (difference.inMinutes < 60) return '${difference.inMinutes}M AGO';
    if (difference.inHours < 24) return '${difference.inHours}H AGO';
    return '${difference.inDays}D AGO';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        feedback.category.toUpperCase(),
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 0.5),
                      ),
                    ),
                    Text(
                      _getTimeAgo(feedback.timestamp),
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: List.generate(5, (i) {
                    return Icon(
                      i < feedback.rating ? Icons.star_rounded : Icons.star_border_rounded,
                      color: i < feedback.rating ? Colors.amber : AppColors.outlineVariant,
                      size: 20,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  '"${feedback.comments}"',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (feedback.userId != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 14, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        'User ID: ${feedback.userId!.substring(0, 8)}...',
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (feedback.status == 'new')
                      TextButton.icon(
                        onPressed: () => FirebaseFirestore.instance.collection('feedbacks').doc(feedback.id).update({'status': 'reviewed'}),
                        icon: const Icon(Icons.visibility),
                        label: const Text('Mark Reviewed'),
                      ),
                    if (feedback.status == 'reviewed')
                      TextButton.icon(
                        onPressed: () => FirebaseFirestore.instance.collection('feedbacks').doc(feedback.id).update({'status': 'resolved'}),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark Resolved'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (feedback.imageUrl != null && feedback.imageUrl!.isNotEmpty) ...[
            const Divider(height: 1, thickness: 1),
            ClipRRect(
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
              child: Image.network(
                feedback.imageUrl!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 100,
                  width: double.infinity,
                  color: AppColors.surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported, color: AppColors.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
