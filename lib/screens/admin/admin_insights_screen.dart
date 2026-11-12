import 'dart:math';
import '../../services/admin_insights.dart';
import '../../l10n/formatters.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/app_state_service.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';

class AdminInsightsScreen extends StatefulWidget {
  final AdminInsightsLoader? load;
  const AdminInsightsScreen({super.key, this.load});

  @override
  State<AdminInsightsScreen> createState() => _AdminInsightsScreenState();
}

class _AdminInsightsScreenState extends State<AdminInsightsScreen>
    with WidgetsBindingObserver {
  late Future<AdminInsightsData> _data;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  void _reload() {
    _data = Future.sync(
      () => (widget.load ?? AdminInsightsService.load)(_is7Days ? 7 : 30),
    );
    _data.ignore();
  }

  void _refresh() => setState(_reload);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _is7Days = true;
  bool _showTable = false;
  int? _selectedBarIndex;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = palette.isDark;

    return Scaffold(
      backgroundColor: isDark ? palette.surface : const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: palette.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          tr(context, 'Insights'),
          style: GoogleFonts.manrope(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: palette.primary,
          ),
        ),
        centerTitle: false,
      ),
      body: FutureBuilder<AdminInsightsData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError || !snapshot.hasData)
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr(
                        context,
                        'Insights unavailable. Connect and refresh; no totals are assumed.',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(tr(context, 'Refresh')),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _is7Days = !_is7Days;
                          _reload();
                        });
                      },
                      child: Text(
                        tr(context, _is7Days ? 'Last 30 days' : 'Last 7 days'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          return _buildBody(
            context,
            snapshot.data!,
            AppStateService.instance.roads,
            isDark,
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AdminInsightsData data,
    List<RoadStatus> allRoads,
    bool isDark,
  ) {
    final periodReports = data.reports;
    final reportCount = data.received;
    final verifiedPercent = data.verifiedPercent;
    final verifiedDisplayCount = data.verified;
    final waitingDisplayCount = data.needsReview;
    final notVerifiedDisplayCount = data.notVerified;
    final chartData = _calculateChartData(data);
    final busiestLabel = reportCount == 0
        ? tr(context, 'No reports in this period.')
        : _getBusiestLabel(chartData);
    final rankedRoads = _getRankedRoads(periodReports, allRoads);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Time range toggle: Last 7 days | Last 30 days
          _buildRangeToggle(isDark),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Text(
                  '${tr(context, 'Checked')}: ${localizedDateTime(context, data.checkedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.of(context).onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                onPressed: _refresh,
                tooltip: tr(context, 'Refresh'),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            tr(
              context,
              'Counts cover submissions in this period. Follow-ups are separate submissions; replies are excluded.',
            ),
          ),
          const SizedBox(height: 12),
          // 2. Dynamic Insight Headline
          Text(
            busiestLabel,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1B2430),
            ),
          ),
          const SizedBox(height: 16),

          // 3. 2x2 Metric Cards Grid
          _buildMetricCards(
            isDark: isDark,
            reportCount: reportCount,
            verifiedPercent: verifiedPercent,
            avgMinutes: data.averageReviewMinutes,
            waitingResident: data.waitingResident,
          ),
          const SizedBox(height: 20),

          // 4. Reports Volume Chart / Table
          _buildReportsChartCard(isDark: isDark, chartData: chartData),
          const SizedBox(height: 20),

          // 5. Roads with most reports
          _buildRankedRoadsCard(isDark: isDark, rankedRoads: rankedRoads),
          const SizedBox(height: 20),

          // 6. What happened to reports (Outcome breakdown)
          _buildOutcomesCard(
            isDark: isDark,
            verifiedCount: verifiedDisplayCount,
            waitingResident: data.waitingResident,
            other: data.other,
            waitingCount: waitingDisplayCount,
            notVerifiedCount: notVerifiedDisplayCount,
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _buildRangeToggle(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E242B) : const Color(0xFFEAEFF5),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!_is7Days) {
                  setState(() {
                    _is7Days = true;
                    _selectedBarIndex = null;
                    _reload();
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _is7Days
                      ? (isDark ? const Color(0xFF2C3440) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: _is7Days
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  tr(context, 'Last 7 days'),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: _is7Days ? FontWeight.w700 : FontWeight.w500,
                    color: _is7Days
                        ? const Color(0xFF0D5BC6)
                        : (isDark ? Colors.white70 : const Color(0xFF5A6474)),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_is7Days) {
                  setState(() {
                    _is7Days = false;
                    _selectedBarIndex = null;
                    _reload();
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !_is7Days
                      ? (isDark ? const Color(0xFF2C3440) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: !_is7Days
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  tr(context, 'Last 30 days'),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: !_is7Days ? FontWeight.w700 : FontWeight.w500,
                    color: !_is7Days
                        ? const Color(0xFF0D5BC6)
                        : (isDark ? Colors.white70 : const Color(0xFF5A6474)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCards({
    required bool isDark,
    required int reportCount,
    required int? verifiedPercent,
    required int? avgMinutes,
    required int waitingResident,
  }) {
    final cardBg = isDark ? const Color(0xFF1E232A) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2D3540)
        : const Color(0xFFE2E7ED);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                backgroundColor: cardBg,
                borderColor: borderColor,
                label: tr(context, 'Reports received'),
                value: '$reportCount',
                subtext: tr(context, 'In selected period'),
                subtextColor: isDark ? Colors.white70 : const Color(0xFF5A6474),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                backgroundColor: cardBg,
                borderColor: borderColor,
                label: tr(context, 'Verified'),
                value: verifiedPercent == null ? '--' : '$verifiedPercent%',
                subtext: tr(context, 'of submitted reports'),
                subtextColor: isDark ? Colors.white70 : const Color(0xFF5A6474),
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                backgroundColor: cardBg,
                borderColor: borderColor,
                label: tr(context, 'Time to review'),
                value: avgMinutes == null
                    ? '--'
                    : avgMinutes == 0
                    ? '<1 min'
                    : '$avgMinutes min',
                subtext: tr(
                  context,
                  avgMinutes == null
                      ? 'No dated completed reviews'
                      : 'Submission to final review',
                ),
                subtextColor: isDark ? Colors.white70 : const Color(0xFF5A6474),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                backgroundColor: cardBg,
                borderColor: borderColor,
                label: tr(context, 'Waiting for resident'),
                value: '$waitingResident',
                subtext: tr(context, 'Clarification requested'),
                subtextColor: isDark ? Colors.white70 : const Color(0xFF5A6474),
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReportsChartCard({
    required bool isDark,
    required List<_ChartBarData> chartData,
  }) {
    final cardBg = isDark ? const Color(0xFF1E232A) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2D3540)
        : const Color(0xFFE2E7ED);

    final title = _is7Days
        ? tr(context, 'Reports per day')
        : tr(context, 'Reports per week');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1B2430),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(context, 'Tap a bar to see the number'),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showTable = !_showTable;
                    });
                  },
                  child: Text(
                    _showTable
                        ? tr(context, 'View as chart')
                        : tr(context, 'View as table'),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0D5BC6),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_showTable)
            _buildTableView(chartData, isDark)
          else
            _buildBarChartView(chartData, isDark),
        ],
      ),
    );
  }

  Widget _buildBarChartView(List<_ChartBarData> chartData, bool isDark) {
    final maxVal = chartData.map((d) => d.count).fold<int>(1, max);

    return SizedBox(
      height: 180 * MediaQuery.textScalerOf(context).scale(12) / 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: chartData.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isSelected = _selectedBarIndex == index;
          final heightFactor = maxVal > 0
              ? (item.count / maxVal).clamp(0.0, 1.0)
              : 0.0;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _selectedBarIndex = _selectedBarIndex == index ? null : index;
                });
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Number badge above selected bar
                  SizedBox(
                    height: 24,
                    child: (isSelected || item.isHighlighted)
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C3440)
                                  : const Color(0xFFEBF2FD),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${item.count}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0D5BC6),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 4),

                  // Bar itself
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: heightFactor,
                        child: Container(
                          width: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2575FC),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Day or Date label below
                  Text(
                    item.label,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF5A6474),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTableView(List<_ChartBarData> chartData, bool isDark) {
    return Column(
      children: chartData.map((item) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1B2430),
                ),
              ),
              Text(
                '${item.count} reports',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0D5BC6),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRankedRoadsCard({
    required bool isDark,
    required List<_RoadRanking> rankedRoads,
  }) {
    final cardBg = isDark ? const Color(0xFF1E232A) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2D3540)
        : const Color(0xFFE2E7ED);

    final maxCount = rankedRoads.map((r) => r.count).fold<int>(1, max);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Roads with the most reports'),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1B2430),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tr(context, 'These roads may need a closer look.'),
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.white60 : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 20),

          if (rankedRoads.isEmpty)
            Text(tr(context, 'No road-linked reports in this period.')),
          ...rankedRoads.map((road) {
            final fraction = maxCount > 0
                ? (road.count / maxCount).clamp(0.08, 1.0)
                : 0.08;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          road.name,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1B2430),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${road.count}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1B2430),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Stack(
                    children: [
                      Container(
                        height: 7,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C3440)
                              : const Color(0xFFEDF2F7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: fraction,
                        child: Container(
                          height: 7,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2575FC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOutcomesCard({
    required bool isDark,
    required int verifiedCount,
    required int waitingCount,
    required int notVerifiedCount,
    required int waitingResident,
    required int other,
  }) {
    final total =
        verifiedCount +
        waitingCount +
        waitingResident +
        notVerifiedCount +
        other;
    int? share(int count) => total == 0 ? null : (count * 100 / total).round();
    final cardBg = isDark ? const Color(0xFF1E232A) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2D3540)
        : const Color(0xFFE2E7ED);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'What happened to reports'),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1B2430),
            ),
          ),
          const SizedBox(height: 16),

          // Stacked horizontal segmented bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (verifiedCount > 0)
                    Expanded(
                      flex: verifiedCount,
                      child: Container(color: const Color(0xFF10A83A)),
                    ),
                  if (waitingCount > 0)
                    Expanded(
                      flex: waitingCount,
                      child: Container(color: const Color(0xFFF9A825)),
                    ),
                  if (waitingResident > 0)
                    Expanded(
                      flex: waitingResident,
                      child: Container(color: const Color(0xFF2575FC)),
                    ),
                  if (notVerifiedCount + other > 0)
                    Expanded(
                      flex: notVerifiedCount + other,
                      child: Container(color: const Color(0xFF888E99)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Verified row
          _buildOutcomeRow(
            icon: Icons.check_circle_outline,
            iconColor: const Color(0xFF10A83A),
            title: tr(context, 'Verified'),
            count: verifiedCount,
            percent: share(verifiedCount),
            isDark: isDark,
          ),
          Divider(
            height: 24,
            color: isDark ? const Color(0xFF2C3440) : const Color(0xFFEDF2F7),
          ),

          // Waiting for review row
          _buildOutcomeRow(
            icon: Icons.access_time,
            iconColor: const Color(0xFFD97706),
            title: tr(context, 'Needs admin review'),
            count: waitingCount,
            percent: share(waitingCount),
            isDark: isDark,
          ),
          Divider(
            height: 24,
            color: isDark ? const Color(0xFF2C3440) : const Color(0xFFEDF2F7),
          ),

          // Not verified row
          _buildOutcomeRow(
            icon: Icons.cancel_outlined,
            iconColor: const Color(0xFF6B7280),
            title: tr(context, 'Not verified'),
            count: notVerifiedCount,
            percent: share(notVerifiedCount),
            isDark: isDark,
          ),
          if (waitingResident > 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _buildOutcomeRow(
                icon: Icons.question_answer_outlined,
                iconColor: const Color(0xFF2575FC),
                title: tr(context, 'Waiting for resident'),
                count: waitingResident,
                percent: share(waitingResident),
                isDark: isDark,
              ),
            ),
          if (other > 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _buildOutcomeRow(
                icon: Icons.info_outline,
                iconColor: const Color(0xFF888E99),
                title: tr(context, 'Other outcomes'),
                count: other,
                percent: share(other),
                isDark: isDark,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOutcomeRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required int count,
    required int? percent,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1B2430),
            ),
          ),
        ),
        Text(
          '$count',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1B2430),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 44 * MediaQuery.textScalerOf(context).scale(14) / 14,
          child: Text(
            percent == null ? '' : '$percent%',
            textAlign: TextAlign.end,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : const Color(0xFF6B7280),
            ),
          ),
        ),
      ],
    );
  }

  List<_ChartBarData> _calculateChartData(AdminInsightsData data) {
    final maximum = data.buckets.map((b) => b.count).fold<int>(0, max);
    return data.buckets
        .map(
          (b) => _ChartBarData(
            label: _is7Days
                ? DateFormat(
                    'MMM d',
                    Localizations.localeOf(context).toLanguageTag(),
                  ).format(b.start)
                : '${DateFormat('MMM d', Localizations.localeOf(context).toLanguageTag()).format(b.start)}?${DateFormat('d', Localizations.localeOf(context).toLanguageTag()).format(b.end.subtract(const Duration(days: 1)))}',
            count: b.count,
            isHighlighted: b.count > 0 && b.count == maximum,
          ),
        )
        .toList();
  }

  String _getBusiestLabel(List<_ChartBarData> chartData) {
    final maximum = chartData.map((b) => b.count).fold<int>(0, max);
    final peaks = chartData.where((b) => b.count == maximum).toList();
    if (maximum == 0) return tr(context, 'No reports in this period.');
    if (peaks.length > 1)
      return tr(
            context,
            'Highest count: {count} submissions across {periods} periods.',
          )
          .replaceAll('{count}', '$maximum')
          .replaceAll('{periods}', '${peaks.length}');
    return tr(context, 'Highest volume: {date} ({count} submissions).')
        .replaceAll('{date}', peaks.single.label)
        .replaceAll('{count}', '$maximum');
  }

  List<_RoadRanking> _getRankedRoads(
    List<UserReport> periodReports,
    List<RoadStatus> allRoads,
  ) {
    final countsByRoadId = <String, int>{};
    for (final r in periodReports) {
      if (r.roadId != null && r.roadId!.isNotEmpty) {
        countsByRoadId[r.roadId!] = (countsByRoadId[r.roadId!] ?? 0) + 1;
      }
    }

    final sortedEntries = countsByRoadId.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final roadMap = {for (final r in allRoads) r.id: r.name};

    return sortedEntries.take(5).map((e) {
      final roadName =
          roadMap[e.key] ?? 'Road ${e.key.substring(0, min(6, e.key.length))}';
      return _RoadRanking(name: roadName, count: e.value);
    }).toList();
  }
}

class _MetricCard extends StatelessWidget {
  final Color backgroundColor;
  final Color borderColor;
  final String label;
  final String value;
  final String subtext;
  final Color subtextColor;
  final bool isDark;

  const _MetricCard({
    required this.backgroundColor,
    required this.borderColor,
    required this.label,
    required this.value,
    required this.subtext,
    required this.subtextColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1B2430),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: subtextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartBarData {
  final String label;
  final int count;
  final bool isHighlighted;

  _ChartBarData({
    required this.label,
    required this.count,
    this.isHighlighted = false,
  });
}

class _RoadRanking {
  final String name;
  final int count;

  _RoadRanking({required this.name, required this.count});
}
