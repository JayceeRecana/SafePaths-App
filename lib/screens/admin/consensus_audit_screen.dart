import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';

class ConsensusAuditScreen extends StatelessWidget {
  const ConsensusAuditScreen({super.key});

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'Unknown Time';
    return DateFormat('MMM d, yyyy • h:mm a').format(ts.toDate());
  }

  Widget _buildSeverityDistribution(Map<String, dynamic> distribution) {
    if (distribution.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Severity Distribution',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: distribution.entries.map((entry) {
            Color pillColor = AppColors.surfaceContainerHigh;
            Color textColor = AppColors.onSurface;
            
            if (entry.key == 'High') {
              pillColor = AppColors.notPassable.withValues(alpha: 0.1);
              textColor = AppColors.notPassable;
            } else if (entry.key == 'Medium') {
              pillColor = AppColors.partial.withValues(alpha: 0.1);
              textColor = AppColors.partial;
            } else if (entry.key == 'Low') {
              pillColor = AppColors.passable.withValues(alpha: 0.1);
              textColor = AppColors.passable;
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: textColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${entry.key}: ${entry.value}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const AppTopBar(title: 'Audit Trail', showBackButton: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('consensus_audits')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error loading audits.', style: GoogleFonts.inter()));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.analytics_outlined, size: 48, color: AppColors.outline),
                  const SizedBox(height: 16),
                  Text(
                    'No consensus audits yet.',
                    style: GoogleFonts.inter(color: AppColors.outline, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              
              final isConsensus = data['alertType'] == 'Consensus Alert';
              final alertColor = isConsensus ? AppColors.error : Colors.orange;

              double agreementRate = (data['agreementRate'] as num?)?.toDouble() ?? 0;
              double averageConfidence = (data['averageConfidence'] as num?)?.toDouble() ?? 0;

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: alertColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: alertColor.withValues(alpha: 0.05),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        border: Border(bottom: BorderSide(color: alertColor.withValues(alpha: 0.1))),
                      ),
                      child: Row(
                        children: [
                          Icon(isConsensus ? Icons.warning_rounded : Icons.pending_actions, color: alertColor, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['roadName'] ?? 'Unknown Road',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatTimestamp(data['timestamp'] as Timestamp?),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: alertColor,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              data['alertType'] ?? 'Alert',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Body
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Metrics Row
                          Row(
                            children: [
                              Expanded(
                                child: _MetricBox(
                                  label: 'Agreement',
                                  value: '${(agreementRate * 100).toStringAsFixed(0)}%',
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (isConsensus) ...[
                                Expanded(
                                  child: _MetricBox(
                                    label: 'Avg Confidence',
                                    value: averageConfidence.toStringAsFixed(1),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: _MetricBox(
                                  label: 'Total Reports',
                                  value: '${data['totalReports'] ?? 0}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          // Severity Distribution
                          if (data['severityDistribution'] != null) ...[
                            _buildSeverityDistribution(Map<String, dynamic>.from(data['severityDistribution'])),
                            const SizedBox(height: 20),
                          ],

                          // Trigger Reason
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Trigger Reason',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  data['triggerReason'] ?? 'Unknown rule',
                                  style: GoogleFonts.firaCode(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Footer metadata
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Road Status Before: ${data['roadStatusAtTime'] ?? 'unknown'}',
                                style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.commit, size: 14, color: AppColors.outline),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${data['algorithmVersion'] ?? 'v1.0'}',
                                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  final String label;
  final String value;

  const _MetricBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
