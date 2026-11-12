import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import '../user/report_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/safe_image.dart';
import '../../services/app_state_service.dart';

class ConsensusAuditScreen extends StatefulWidget {
  final int initialTabIndex;
  const ConsensusAuditScreen({super.key, this.initialTabIndex = 0});

  @override
  State<ConsensusAuditScreen> createState() => _ConsensusAuditScreenState();
}

class _ConsensusAuditScreenState extends State<ConsensusAuditScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  String _reporterFilter = 'all'; // 'all', 'high', 'standard', 'flagged'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'Unknown Time';
    return DateFormat('MMM d, yyyy • h:mm a').format(ts.toDate());
  }

  String _formatDate(DateTime dt) {
    return DateFormat('MMM d, yyyy • h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).surface,
      appBar: AppTopBar(
        title: tr(context, 'Reporters & Audits'),
        showBackButton: true,
      ),
      body: Column(
        children: [
          // Tab Bar (Reporters first!)
          Container(
            color: AppPalette.of(context).surface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppPalette.of(context).primary,
              unselectedLabelColor: AppPalette.of(context).onSurfaceVariant,
              indicatorColor: AppPalette.of(context).primary,
              indicatorWeight: 3,
              labelStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              unselectedLabelStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.people_alt_rounded, size: 20),
                  text: 'Community Reporters',
                ),
                Tab(
                  icon: Icon(Icons.history_edu_rounded, size: 20),
                  text: 'Incident & System Audits',
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppPalette.of(context).outlineVariant),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCommunityReportersTab(),
                _buildIncidentAuditsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 1: COMMUNITY REPORTERS DIRECTORY ───────────────────────────

  Widget _buildCommunityReportersTab() {
    return ListenableBuilder(
      listenable: AppStateService.instance,
      builder: (context, _) {
        final allUsers = AppStateService.instance.users;

        var reporters = allUsers.where((u) {
          if (_searchQuery.isNotEmpty) {
            final query = _searchQuery.toLowerCase();
            final matchesName = u.name.toLowerCase().contains(query);
            final matchesEmail = u.email.toLowerCase().contains(query);
            if (!matchesName && !matchesEmail) return false;
          }

          if (_reporterFilter == 'high') {
            return u.trustScore >= 80;
          } else if (_reporterFilter == 'standard') {
            return u.trustScore >= 40 && u.trustScore < 80;
          } else if (_reporterFilter == 'flagged') {
            return u.trustScore < 40 || u.dismissedReports > 0;
          }
          return true;
        }).toList();

        reporters.sort((a, b) {
          if (b.trustScore != a.trustScore)
            return b.trustScore.compareTo(a.trustScore);
          return b.verifiedReports.compareTo(a.verifiedReports);
        });

        final totalVerified = allUsers.fold<int>(
          0,
          (sum, u) => sum + u.verifiedReports,
        );
        final avgTrust = allUsers.isNotEmpty
            ? (allUsers.fold<int>(0, (sum, u) => sum + u.trustScore) /
                      allUsers.length)
                  .toStringAsFixed(1)
            : '0.0';

        return CustomScrollView(
          slivers: [
            // Top Metrics Summary Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppPalette.of(
                        context,
                      ).outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SummaryStat(
                          icon: Icons.people_alt_rounded,
                          color: AppPalette.of(context).primary,
                          label: tr(context, 'Reporters'),
                          value: '${allUsers.length}',
                        ),
                      ),
                      Container(
                        height: 36,
                        width: 1,
                        color: AppPalette.of(context).outlineVariant,
                      ),
                      Expanded(
                        child: _SummaryStat(
                          icon: Icons.verified_rounded,
                          color: AppPalette.of(context).secondary,
                          label: tr(context, 'Approved'),
                          value: '$totalVerified',
                        ),
                      ),
                      Container(
                        height: 36,
                        width: 1,
                        color: AppPalette.of(context).outlineVariant,
                      ),
                      Expanded(
                        child: _SummaryStat(
                          icon: Icons.shield_rounded,
                          color: Colors.orange,
                          label: tr(context, 'Avg Trust'),
                          value: avgTrust,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Search Bar & Filter Chips
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: tr(
                          context,
                          'Search reporters by name or email...',
                        ),
                        hintStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppPalette.of(context).onSurfaceVariant,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 20,
                          color: AppPalette.of(context).onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: AppPalette.of(context).surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) =>
                          setState(() => _searchQuery = val.trim()),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChipButton(
                            label: 'All (${allUsers.length})',
                            isSelected: _reporterFilter == 'all',
                            onTap: () =>
                                setState(() => _reporterFilter = 'all'),
                          ),
                          const SizedBox(width: 8),
                          _FilterChipButton(
                            label: tr(context, 'Top Trust (80+)'),
                            isSelected: _reporterFilter == 'high',
                            activeColor: AppPalette.of(context).secondary,
                            onTap: () =>
                                setState(() => _reporterFilter = 'high'),
                          ),
                          const SizedBox(width: 8),
                          _FilterChipButton(
                            label: tr(context, 'Standard (40-79)'),
                            isSelected: _reporterFilter == 'standard',
                            activeColor: AppPalette.of(context).primary,
                            onTap: () =>
                                setState(() => _reporterFilter = 'standard'),
                          ),
                          const SizedBox(width: 8),
                          _FilterChipButton(
                            label: tr(context, 'Flagged / Low Trust'),
                            isSelected: _reporterFilter == 'flagged',
                            activeColor: AppPalette.of(context).error,
                            onTap: () =>
                                setState(() => _reporterFilter = 'flagged'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Reporters List
            if (reporters.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_search_rounded,
                        size: 48,
                        color: AppPalette.of(context).outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(context, 'No reporters match criteria'),
                        style: GoogleFonts.inter(
                          color: AppPalette.of(context).onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final user = reporters[index];
                    final int totalReports =
                        user.verifiedReports + user.dismissedReports;
                    final double accuracyRate = totalReports > 0
                        ? (user.verifiedReports / totalReports) * 100
                        : 100.0;

                    int trustLevel = 3;
                    Color trustColor = Colors.orange;
                    if (user.trustScore >= 80) {
                      trustLevel = 5;
                      trustColor = AppPalette.of(context).secondary;
                    } else if (user.trustScore >= 60) {
                      trustLevel = 4;
                      trustColor = Colors.teal;
                    } else if (user.trustScore >= 40) {
                      trustLevel = 3;
                      trustColor = Colors.orange;
                    } else if (user.trustScore >= 20) {
                      trustLevel = 2;
                      trustColor = Colors.deepOrange;
                    } else {
                      trustLevel = 1;
                      trustColor = AppPalette.of(context).error;
                    }

                    String initials = 'AN';
                    if (user.name.isNotEmpty) {
                      final parts = user.name.trim().split(' ');
                      if (parts.length > 1) {
                        initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
                      } else {
                        initials = user.name
                            .substring(0, user.name.length >= 2 ? 2 : 1)
                            .toUpperCase();
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppPalette.of(context).surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: user.trustScore < 40
                              ? AppPalette.of(
                                  context,
                                ).error.withValues(alpha: 0.3)
                              : AppPalette.of(
                                  context,
                                ).outlineVariant.withValues(alpha: 0.25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _showReporterHistorySheet(context, user),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    user.photoUrl != null &&
                                            user.photoUrl!.isNotEmpty
                                        ? UserAvatar(
                                            photoUrl: user.photoUrl,
                                            size: 40,
                                            iconSize: 20,
                                          )
                                        : CircleAvatar(
                                            radius: 20,
                                            backgroundColor: trustColor
                                                .withValues(alpha: 0.15),
                                            child: Text(
                                              initials,
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w800,
                                                color: trustColor,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user.name.isNotEmpty
                                                ? user.name
                                                : tr(
                                                    context,
                                                    'Citizen Reporter',
                                                  ),
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              color: AppPalette.of(
                                                context,
                                              ).onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            user.email.isNotEmpty
                                                ? user.email
                                                : user.id,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: AppPalette.of(
                                                context,
                                              ).onSurfaceVariant,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: trustColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: trustColor.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'Level $trustLevel • ${user.trustScore} pts',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                          color: trustColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                // Progress Bar
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: user.trustScore / 100.0,
                                    minHeight: 6,
                                    backgroundColor: AppPalette.of(
                                      context,
                                    ).surfaceContainerHighest,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      trustColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Stats Footer
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          size: 14,
                                          color: AppPalette.of(
                                            context,
                                          ).secondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${user.verifiedReports} approved',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppPalette.of(
                                              context,
                                            ).onSurface,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(
                                          Icons.cancel,
                                          size: 14,
                                          color: user.dismissedReports > 0
                                              ? AppPalette.of(context).error
                                              : AppPalette.of(context).outline,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${user.dismissedReports} dismissed',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: AppPalette.of(
                                              context,
                                            ).onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          tr(context, 'View History'),
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: AppPalette.of(
                                              context,
                                            ).primary,
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          size: 10,
                                          color: AppPalette.of(context).primary,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }, childCount: reporters.length),
                ),
              ),
          ],
        );
      },
    );
  }

  // ─── CITIZEN REPORTER HISTORY BOTTOM SHEET ──────────────────────────

  void _showReporterHistorySheet(BuildContext context, UserProfile user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return ListenableBuilder(
              listenable: AppStateService.instance,
              builder: (context, _) {
                // Find all reports by this citizen
                final allUserReports = AppStateService.instance.reports
                    .where((r) => r.userId == user.id)
                    .toList();
                final approvedReports = allUserReports
                    .where((r) => r.status == 'verified')
                    .toList();
                final otherReports = allUserReports
                    .where((r) => r.status != 'verified')
                    .toList();

                return Column(
                  children: [
                    // Sheet Drag Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).outlineVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    // Sheet Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              user.photoUrl != null && user.photoUrl!.isNotEmpty
                                  ? UserAvatar(
                                      photoUrl: user.photoUrl,
                                      size: 44,
                                      iconSize: 22,
                                    )
                                  : Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppPalette.of(
                                          context,
                                        ).primary.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        user.name.isNotEmpty
                                            ? user.name
                                                  .substring(0, 1)
                                                  .toUpperCase()
                                            : tr(context, 'C'),
                                        style: GoogleFonts.manrope(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: AppPalette.of(context).primary,
                                        ),
                                      ),
                                    ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.name.isNotEmpty
                                        ? user.name
                                        : tr(context, 'Citizen Reporter'),
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppPalette.of(context).onSurface,
                                    ),
                                  ),
                                  Text(
                                    user.email.isNotEmpty
                                        ? user.email
                                        : 'Citizen ID: ${user.id.length >= 8 ? user.id.substring(0, 8) : user.id}...',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppPalette.of(
                                        context,
                                      ).onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppPalette.of(
                                context,
                              ).secondary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: AppPalette.of(
                                  context,
                                ).secondary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '${user.trustScore}% Trust',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.of(context).secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: AppPalette.of(context).outlineVariant,
                    ),

                    // Reports List
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(20),
                        children: [
                          // Section: Approved Reports
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'LOADED VERIFIED REPORTS (${approvedReports.length})',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: AppPalette.of(context).secondary,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppPalette.of(
                                    context,
                                  ).secondary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tr(context, '+10 pts / each'),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppPalette.of(context).secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          if (approvedReports.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppPalette.of(
                                  context,
                                ).surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.center,
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.verified_outlined,
                                    size: 36,
                                    color: AppPalette.of(context).outline,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    tr(
                                      context,
                                      'No verified reports in the live view. Open history for older reports.',
                                    ),
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppPalette.of(
                                        context,
                                      ).onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            ...approvedReports.map(
                              (report) => _buildApprovedReportCard(report),
                            ),

                          TextButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ReportHistoryScreen(userId: user.id),
                              ),
                            ),
                            icon: const Icon(Icons.history),
                            label: Text(
                              tr(context, 'Open complete report history'),
                            ),
                          ),
                          // Section: Other / Pending / Dismissed Reports
                          if (otherReports.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(
                              'CURRENT ACTIVITY (${otherReports.length})',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: AppPalette.of(context).onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...otherReports.map(
                              (report) => _buildApprovedReportCard(report),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildApprovedReportCard(UserReport report) {
    final isVerified = report.status == 'verified';
    final isDismissed = report.status == 'dismissed';

    Color statusColor = AppPalette.of(context).primary;
    String statusLabel = 'PENDING REVIEW';
    if (isVerified) {
      statusColor = AppPalette.of(context).secondary;
      statusLabel = 'VERIFIED BY COMMAND';
    } else if (isDismissed) {
      statusColor = AppPalette.of(context).error;
      statusLabel = 'DISMISSED';
    }

    String roadName = 'Monitored Road';
    try {
      final found = AppStateService.instance.roads.firstWhere(
        (r) => r.id == report.roadId,
      );
      roadName = found.name;
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVerified
                          ? Icons.check_circle
                          : (isDismissed ? Icons.cancel : Icons.schedule),
                      size: 12,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatDate(report.createdAt),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.of(context).outlineVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Road & Title
          Row(
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 15,
                color: AppPalette.of(context).primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  roadName,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.of(context).onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Citizen Message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppPalette.of(
                context,
              ).surfaceContainerHigh.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(color: statusColor, width: 3)),
            ),
            child: Text(
              '"${report.description}"',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppPalette.of(context).onSurface,
              ),
            ),
          ),

          // Photo Evidence (if any)
          if (report.imageUrl != null && report.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            SafeImage(
              imageUrl: report.imageUrl,
              height: 110,
              width: double.infinity,
              borderRadius: BorderRadius.circular(10),
            ),
          ],

          // Admin Sent Reply (if any)
          if (report.adminReply != null && report.adminReply!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppPalette.of(context).primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.reply_rounded,
                    size: 13,
                    color: AppPalette.of(context).primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Admin Note: "${report.adminReply}"',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.of(context).primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── TAB 2: INCIDENT & SYSTEM AUDITS ─────────────────────────────────

  Widget _buildIncidentAuditsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('consensus_audits')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: AppPalette.of(context).primary,
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              tr(context, 'Error loading audits.'),
              style: GoogleFonts.inter(),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.analytics_outlined,
                  size: 48,
                  color: AppPalette.of(context).outline,
                ),
                const SizedBox(height: 16),
                Text(
                  tr(context, 'No incident audits recorded yet.'),
                  style: GoogleFonts.inter(
                    color: AppPalette.of(context).onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;

            final action = data['action'] as String?;
            final alertType =
                (data['alertType'] as String?) ??
                (action == 'verified' ? 'Report Verified' : 'Consensus Audit');

            Color alertColor = AppPalette.of(context).primary;
            IconData auditIcon = Icons.shield_outlined;

            if (action == 'verified' || alertType == 'Report Verified') {
              alertColor = AppPalette.of(context).secondary;
              auditIcon = Icons.verified_rounded;
            } else if (action == 'dismissed' ||
                alertType == 'Report Dismissed') {
              alertColor = AppPalette.of(context).error;
              auditIcon = Icons.cancel_outlined;
            } else if (alertType == 'Consensus Alert') {
              alertColor = AppPalette.of(context).notPassable;
              auditIcon = Icons.warning_rounded;
            } else if (alertType == 'Under Verification') {
              alertColor = Colors.orange;
              auditIcon = Icons.hourglass_top_rounded;
            }

            return Container(
              decoration: BoxDecoration(
                color: AppPalette.of(context).surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: alertColor.withValues(alpha: 0.25)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: alertColor.withValues(alpha: 0.06),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: alertColor.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(auditIcon, color: alertColor, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['roadName'] ??
                                    tr(context, 'Monitored Road'),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: AppPalette.of(context).onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatTimestamp(
                                  data['timestamp'] as Timestamp?,
                                ),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppPalette.of(
                                    context,
                                  ).onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: alertColor,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            alertType.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Body
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Trigger Reason / Action Description
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppPalette.of(
                              context,
                            ).surfaceContainerHigh.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: alertColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  data['triggerReason'] ??
                                      (data['action'] != null
                                          ? 'Action: ${data['action']}'
                                          : 'Consensus rule triggered'),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppPalette.of(context).onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Consensus metrics (if applicable)
                        if (data['agreementRate'] != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _MetricBox(
                                  label: tr(context, 'Agreement'),
                                  value:
                                      '${((data['agreementRate'] as num).toDouble() * 100).toStringAsFixed(0)}%',
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (data['averageConfidence'] != null) ...[
                                Expanded(
                                  child: _MetricBox(
                                    label: tr(context, 'Avg Conf'),
                                    value: (data['averageConfidence'] as num)
                                        .toDouble()
                                        .toStringAsFixed(1),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: _MetricBox(
                                  label: tr(context, 'Reports'),
                                  value: '${data['totalReports'] ?? 0}',
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Audit Footer Metadata
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (data['performedByUid'] != null)
                              Text(
                                'Moderator: ${(data['performedByUid'] as String).substring(0, 6)}...',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppPalette.of(context).outlineVariant,
                                ),
                              )
                            else
                              Text(
                                'Engine: ${data['algorithmVersion'] ?? 'Auto'}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppPalette.of(context).outlineVariant,
                                ),
                              ),
                            if (data['pointsAwarded'] != null)
                              Text(
                                '+${data['pointsAwarded']} pts awarded',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.of(context).secondary,
                                ),
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
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _SummaryStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppPalette.of(context).onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppPalette.of(context).onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.isSelected,
    this.activeColor = AppColors.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : AppPalette.of(context).surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? activeColor
                : AppPalette.of(context).outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? activeColor
                : AppPalette.of(context).onSurfaceVariant,
          ),
        ),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppPalette.of(
          context,
        ).surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppPalette.of(context).onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppPalette.of(context).onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
