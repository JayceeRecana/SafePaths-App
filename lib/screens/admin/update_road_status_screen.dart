import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import '../../services/weather_service.dart';
import '../shared/full_screen_map_screen.dart';

class UpdateRoadStatusScreen extends StatefulWidget {
  final String? prefilledRoadId;
  final String? reportIdToVerify;
  final String? suggestedStatus;
  final bool isStandalone;
  final bool autoFocusSearch;
  final Function(bool)? onSelectionChanged;

  const UpdateRoadStatusScreen({
    super.key,
    this.prefilledRoadId,
    this.reportIdToVerify,
    this.suggestedStatus,
    this.isStandalone = false,
    this.autoFocusSearch = false,
    this.onSelectionChanged,
  });

  @override
  State<UpdateRoadStatusScreen> createState() => _UpdateRoadStatusScreenState();
}

class _UpdateRoadStatusScreenState extends State<UpdateRoadStatusScreen> {
  // ─── Selection State ───────────────────────────────────────────────────
  String? _selectedRoadId;
  String _selectedStatus = 'passable';
  String _selectedVulnerability = 'low';
  final _notesController = TextEditingController();

  // ─── Multi-select State ────────────────────────────────────────────────
  bool _isMultiSelectMode = false;
  Set<String> _selectedRoadIds = {};

  // ─── Operation State ──────────────────────────────────────────────────
  bool _isSubmitting = false;
  Map<String, dynamic>? _lastState;
  List<Map<String, dynamic>>? _lastMultiState;

  // ─── Search & Filter State ────────────────────────────────────────────
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterStatus = 'all';

  // ─── UI State ─────────────────────────────────────────────────────────
  bool _showAdvancedOptions = false;
  bool _lastHasSelection = false;

  @override
  void initState() {
    super.initState();
    _selectedRoadId = widget.prefilledRoadId;

    if (_selectedRoadId != null) {
      final road = AppStateService.instance.roads.cast<RoadStatus?>().firstWhere(
        (r) => r?.id == _selectedRoadId,
        orElse: () => null,
      );
      if (road != null) {
        _selectedStatus = road.status;
        _selectedVulnerability = road.vulnerability;
        _notesController.text = road.notes == 'Imported from OSM' ? '' : road.notes;
      }
    }

    if (widget.suggestedStatus != null) {
      _selectedStatus = widget.suggestedStatus!;
    }

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─── BUSINESS LOGIC ───────────────────────────────────────────────────

  void _submit() async {
    if (!_isMultiSelectMode && _selectedRoadId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a road.')),
      );
      return;
    }
    if (_isMultiSelectMode && _selectedRoadIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one road.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (_isMultiSelectMode) {
        _lastMultiState = [];
        int successCount = 0;
        Set<String> validIds = {};

        for (String rid in _selectedRoadIds) {
          final prevRoad = AppStateService.instance.roads.cast<RoadStatus?>().firstWhere(
            (r) => r?.id == rid,
            orElse: () => null,
          );
          if (prevRoad == null) continue;

          validIds.add(rid);
          _lastMultiState!.add({
            'id': prevRoad.id,
            'status': prevRoad.status,
            'notes': prevRoad.notes,
            'vulnerability': prevRoad.vulnerability,
          });
          successCount++;
        }

        if (validIds.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected roads no longer exist.')),
          );
          return;
        }

        await AppStateService.instance.updateMultipleRoadStatus(
          validIds,
          _selectedStatus,
          _notesController.text.trim(),
          vulnerability: _selectedVulnerability,
        );

        if (!mounted) return;
        final currentLastMultiState = _lastMultiState;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successCount roads updated successfully.'),
            action: currentLastMultiState != null
                ? SnackBarAction(
                    label: 'UNDO',
                    onPressed: () async {
                      try {
                        for (var oldState in currentLastMultiState) {
                          await AppStateService.instance.updateRoadStatus(
                            oldState['id'],
                            oldState['status'],
                            oldState['notes'],
                            vulnerability: oldState['vulnerability'],
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to undo changes. Please try again.')),
                          );
                        }
                      }
                    },
                  )
                : null,
          ),
        );
      } else {
        final prevRoad = AppStateService.instance.roads.cast<RoadStatus?>().firstWhere(
          (r) => r?.id == _selectedRoadId,
          orElse: () => null,
        );

        if (prevRoad == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This road no longer exists — please reselect')),
          );
          return;
        }

        _lastState = {
          'id': prevRoad.id,
          'status': prevRoad.status,
          'notes': prevRoad.notes,
          'vulnerability': prevRoad.vulnerability,
        };

        await AppStateService.instance.updateRoadStatus(
          _selectedRoadId!,
          _selectedStatus,
          _notesController.text.trim(),
          vulnerability: _selectedVulnerability,
        );

        if (widget.reportIdToVerify != null) {
          await AppStateService.instance.resolveReport(widget.reportIdToVerify!);
        }

        if (!mounted) return;

        final currentLastState = _lastState;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Road status updated successfully.'),
            action: currentLastState != null
                ? SnackBarAction(
                    label: 'UNDO',
                    onPressed: () async {
                      try {
                        await AppStateService.instance.updateRoadStatus(
                          currentLastState['id'],
                          currentLastState['status'],
                          currentLastState['notes'],
                          vulnerability: currentLastState['vulnerability'],
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to undo changes. Please try again.')),
                          );
                        }
                      }
                    },
                  )
                : null,
          ),
        );
      }

      if (widget.isStandalone || Navigator.canPop(context)) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          if (_isMultiSelectMode) {
            _selectedRoadIds.clear();
            _isMultiSelectMode = false;
          }
        });
      }
    }
  }

  void _deleteRoad() async {
    if (_selectedRoadId == null) return;

    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Road?'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: const Text('Are you sure you want to permanently delete this road from the database?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete', style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() => _isSubmitting = true);
    try {
      await AppStateService.instance.deleteRoadStatus(_selectedRoadId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Road deleted.')));
        setState(() {
          _selectedRoadId = null;
          _showAdvancedOptions = false;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── SELECTION HANDLERS ──────────────────────────────────────────────

  void _handleSingleSelection(String id, RoadStatus road) {
    if (_selectedRoadId == id) {
      // Tap again to deselect
      setState(() {
        _selectedRoadId = null;
        _showAdvancedOptions = false;
      });
      return;
    }

    setState(() {
      _selectedRoadId = id;
      _selectedStatus = road.status;
      _selectedVulnerability = road.vulnerability;
      _notesController.text = road.notes == 'Imported from OSM' ? '' : road.notes;
    });
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      _showAdvancedOptions = false; // reset UI state
      if (!_isMultiSelectMode) {
        _selectedRoadIds.clear();
      } else {
        if (_selectedRoadId != null) {
          _selectedRoadIds.add(_selectedRoadId!);
          _selectedRoadId = null;
        }
      }
    });
  }

  // ─── FILTER LOGIC ────────────────────────────────────────────────────

  List<RoadStatus> _applyFilters(List<RoadStatus> allRoads) {
    var roads = List.of(allRoads);
    final weatherState = SimulatedWeatherService.instance.currentState;
    
    if (_searchQuery.isNotEmpty) {
      roads = roads.where((r) => r.name.toLowerCase().contains(_searchQuery)).toList();
    }
    if (_filterStatus == 'affected') {
      roads = roads.where((r) {
        final st = r.getEffectiveStatus(weatherState);
        return st == 'partial' || st == 'not_passable';
      }).toList();
    } else if (_filterStatus == 'vulnerable') {
      roads = roads.where((r) => r.vulnerability == 'high' || r.riskCategory == 'High').toList();
    } else if (_filterStatus == 'passable') {
      roads = roads.where((r) => r.getEffectiveStatus(weatherState) == 'passable').toList();
    } else if (_filterStatus == 'partial') {
      roads = roads.where((r) => r.getEffectiveStatus(weatherState) == 'partial').toList();
    } else if (_filterStatus == 'not_passable') {
      roads = roads.where((r) => r.getEffectiveStatus(weatherState) == 'not_passable').toList();
    } else if (_filterStatus == 'needs_update') {
      final now = DateTime.now();
      roads = roads.where((r) => now.difference(r.updatedAt).inHours >= 1).toList();
    }
    roads.sort((a, b) => a.name.compareTo(b.name));
    return roads;
  }

  void _onFilterChanged(String newFilter) {
    setState(() => _filterStatus = newFilter);
    final roads = _applyFilters(AppStateService.instance.roads);
    if (_isMultiSelectMode) {
      final visibleIds = roads.map((r) => r.id).toSet();
      _selectedRoadIds = _selectedRoadIds.intersection(visibleIds);
    } else {
      if (roads.isNotEmpty && !roads.any((r) => r.id == _selectedRoadId)) {
        // Unselect if filtered out
        setState(() {
          _selectedRoadId = null;
          _showAdvancedOptions = false;
        });
      }
    }
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────

  String _getTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'partial':
        return AppColors.partial;
      case 'not_passable':
        return AppColors.notPassable;
      default:
        return AppColors.secondary;
    }
  }

  Color _getRiskColor(String category) {
    switch (category) {
      case 'Critical':
        return AppColors.notPassable;
      case 'Warning':
        return AppColors.partial;
      case 'Watch':
        return Colors.orange;
      default:
        return AppColors.secondary;
    }
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'not_passable':
        return 'Impassable';
      case 'partial':
        return 'Partial';
      default:
        return 'Passable';
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 100;

    return Scaffold(
      appBar: AppTopBar(
        title: 'Update Road',
        showBackButton: widget.isStandalone || Navigator.canPop(context),
        showProfile: true,
        showSettingsAction: true,
        onBackPressed: (widget.isStandalone || Navigator.canPop(context))
            ? () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              }
            : null,
      ),
      backgroundColor: AppColors.surfaceContainerLowest, // Lighter background for premium feel
      body: ListenableBuilder(
        listenable: AppStateService.instance,
        builder: (context, _) {
          final roads = _applyFilters(AppStateService.instance.roads);
          final bool hasSelection = _isMultiSelectMode ? _selectedRoadIds.isNotEmpty : _selectedRoadId != null;

          if (hasSelection != _lastHasSelection) {
            _lastHasSelection = hasSelection;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onSelectionChanged?.call(hasSelection);
            });
          }

          return Stack(
            children: [
              // 1. IMMERSIVE LIST (Bottom Layer)
              _buildImmersiveList(roads, hasSelection),

              // 2. FLOATING SEARCH BAR (Top Layer - Glassmorphism)
              if (!keyboardUp)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        color: AppColors.surfaceContainerLowest.withValues(alpha: 0.8),
                        padding: const EdgeInsets.only(top: 12, bottom: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildFloatingSearchBar(),
                            _buildFilterChips(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // 3. FLOATING ACTION CARD (Animated from bottom)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: Curves.fastOutSlowIn,
                bottom: hasSelection ? 16 : -500,
                left: 16,
                right: 16,
                child: _buildFloatingActionCard(),
              ),

              if (_isSubmitting) _buildLoadingOverlay(),
            ],
          );
        },
      ),
    );
  }

  // ─── FLOATING TOP COMPONENTS ─────────────────────────────────────────

  Widget _buildFloatingSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: TextField(
                controller: _searchController,
                autofocus: widget.autoFocusSearch,
                decoration: InputDecoration(
                  hintText: 'Search roads...',
                  hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant),
                  prefixIcon: const Icon(Icons.search, color: AppColors.onSurfaceVariant, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  fillColor: AppColors.surface,
                  filled: true,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20), // More rounded
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Multi-select Toggle Button
          _TopCircleButton(
            icon: Icons.checklist_rounded,
            isActive: _isMultiSelectMode,
            onTap: _toggleMultiSelectMode,
            tooltip: 'Multi-select',
          ),
          const SizedBox(width: 8),
          // Map Button
          _TopCircleButton(
            icon: Icons.map_rounded,
            isActive: false,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FullScreenMapScreen()),
              );
            },
            tooltip: 'Live Map',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none, // Allow shadows to show
        child: Row(
          children: [
            _FilterChip(label: 'All', icon: Icons.list, isSelected: _filterStatus == 'all', onTap: () => _onFilterChanged('all')),
            const SizedBox(width: 8),
            _FilterChip(label: 'Stale', icon: Icons.update, isSelected: _filterStatus == 'needs_update', onTap: () => _onFilterChanged('needs_update'), activeColor: Colors.orange),
            const SizedBox(width: 8),
            _FilterChip(label: 'Passable', icon: Icons.check_circle, isSelected: _filterStatus == 'passable', onTap: () => _onFilterChanged('passable'), activeColor: AppColors.secondary),
            const SizedBox(width: 8),
            _FilterChip(label: 'Partial', icon: Icons.info, isSelected: _filterStatus == 'partial', onTap: () => _onFilterChanged('partial'), activeColor: AppColors.partial),
            const SizedBox(width: 8),
            _FilterChip(label: 'Impassable', icon: Icons.warning, isSelected: _filterStatus == 'not_passable', onTap: () => _onFilterChanged('not_passable'), activeColor: AppColors.notPassable),
            const SizedBox(width: 8),
            _FilterChip(label: 'Affected', icon: Icons.warning_amber_rounded, isSelected: _filterStatus == 'affected', onTap: () => _onFilterChanged('affected'), activeColor: Colors.deepOrange),
            const SizedBox(width: 8),
            _FilterChip(label: 'Vulnerable', icon: Icons.local_fire_department_outlined, isSelected: _filterStatus == 'vulnerable', onTap: () => _onFilterChanged('vulnerable'), activeColor: Colors.purple),
          ],
        ),
      ),
    );
  }

  // ─── IMMERSIVE LIST ──────────────────────────────────────────────────

  Widget _buildImmersiveList(List<RoadStatus> roads, bool hasSelection) {
    if (roads.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty ? 'No roads match "$_searchQuery"' : 'No roads found',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final reports = AppStateService.instance.reports;
    // Add bottom padding so the last items aren't covered by the floating card
    final bottomPadding = hasSelection ? (_showAdvancedOptions ? 420.0 : 280.0) : 40.0;

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 130, 16, bottomPadding), // Top padding for floating bar
      itemCount: roads.length,
      itemBuilder: (context, index) {
        final road = roads[index];
        final isSelected = _isMultiSelectMode ? _selectedRoadIds.contains(road.id) : _selectedRoadId == road.id;
        final weatherState = SimulatedWeatherService.instance.currentState;
        final effectiveStatus = road.getEffectiveStatus(weatherState);
        final isWeatherEscalated = effectiveStatus != road.status && road.status == 'passable';
        final statusColor = _getStatusColor(effectiveStatus);
        final pendingCount = reports.where((r) => r.roadId == road.id && r.status == 'pending').length;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            label: '${road.name}, status: ${road.status}',
            selected: isSelected,
            button: true,
            child: GestureDetector(
              onTap: () {
                if (_isMultiSelectMode) {
                  final newIds = Set<String>.from(_selectedRoadIds);
                  if (newIds.contains(road.id)) {
                    newIds.remove(road.id);
                  } else {
                    newIds.add(road.id);
                  }
                  setState(() => _selectedRoadIds = newIds);
                } else {
                  _handleSingleSelection(road.id, road);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surface,
                  borderRadius: BorderRadius.circular(16), // Softer corners
                  boxShadow: [
                    if (!isSelected)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                  ],
                  border: Border.all(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Status dot
                    ExcludeSemantics(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Road info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  road.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                    color: AppColors.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isWeatherEscalated)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.water_drop, size: 10, color: Colors.blue),
                                      const SizedBox(width: 4),
                                      Text('Escalated', style: GoogleFonts.inter(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                _getTimeAgo(road.updatedAt),
                                style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
                              ),
                              if (road.riskScore > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getRiskColor(road.riskCategory).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    road.riskCategory,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _getRiskColor(road.riskCategory),
                                    ),
                                  ),
                                ),
                              ],
                              if (pendingCount > 0) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.description_outlined, size: 14, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '$pendingCount',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Selection indicator
                    if (_isMultiSelectMode)
                      Checkbox(
                        value: isSelected,
                        onChanged: (_) {
                          final newIds = Set<String>.from(_selectedRoadIds);
                          if (newIds.contains(road.id)) {
                            newIds.remove(road.id);
                          } else {
                            newIds.add(road.id);
                          }
                          setState(() => _selectedRoadIds = newIds);
                        },
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      )
                    else if (isSelected)
                      const Icon(Icons.check_circle, size: 24, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── FLOATING ACTION CARD ─────────────────────────────────────────────

  Widget _buildFloatingActionCard() {
    RoadStatus? selectedRoad;
    if (!_isMultiSelectMode && _selectedRoadId != null) {
      selectedRoad = AppStateService.instance.roads.cast<RoadStatus?>().firstWhere(
            (r) => r?.id == _selectedRoadId,
            orElse: () => null,
          );
    }

    final bool hasSelection = _isMultiSelectMode ? _selectedRoadIds.isNotEmpty : _selectedRoadId != null;
    if (!hasSelection) return const SizedBox.shrink(); // Hide totally if empty

    final bool statusChanged = selectedRoad != null && _selectedStatus != selectedRoad.status;
    final bool vulnChanged = selectedRoad != null && _selectedVulnerability != selectedRoad.vulnerability;
    final hasGeometry = selectedRoad?.geometry != null && selectedRoad!.geometry!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28), // Beautiful large radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 30,
            spreadRadius: 4,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info banner
                _buildInfoBanner(selectedRoad),

                // Geometry warning
                if (selectedRoad != null && !hasGeometry && !_isMultiSelectMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'No geometry — won\'t display on map',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.orange[800]),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Status Buttons
                Row(
                  children: [
                    _CompactStatusButton(
                      icon: Icons.check_circle,
                      label: 'Passable',
                      color: AppColors.secondary,
                      isSelected: _selectedStatus == 'passable',
                      onTap: () => setState(() => _selectedStatus = 'passable'),
                    ),
                    const SizedBox(width: 8),
                    _CompactStatusButton(
                      icon: Icons.info,
                      label: 'Partial',
                      color: AppColors.partial,
                      isSelected: _selectedStatus == 'partial',
                      onTap: () => setState(() => _selectedStatus = 'partial'),
                    ),
                    const SizedBox(width: 8),
                    _CompactStatusButton(
                      icon: Icons.warning,
                      label: 'Impassable',
                      color: AppColors.notPassable,
                      isSelected: _selectedStatus == 'not_passable',
                      onTap: () => setState(() => _selectedStatus = 'not_passable'),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Expandable Advanced Options
                GestureDetector(
                  onTap: () => setState(() => _showAdvancedOptions = !_showAdvancedOptions),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _showAdvancedOptions ? 'Hide Details' : 'Add Details (Notes & Flood Info)',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _showAdvancedOptions ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.primary,
                        )
                      ],
                    ),
                  ),
                ),

                // Animated Advanced Section
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _showAdvancedOptions
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 16),
                            Text(
                              'FLOOD VULNERABILITY',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _CompactStatusButton(
                                  icon: Icons.terrain,
                                  label: 'Low',
                                  color: AppColors.secondary,
                                  isSelected: _selectedVulnerability == 'low',
                                  onTap: () => setState(() => _selectedVulnerability = 'low'),
                                ),
                                const SizedBox(width: 8),
                                _CompactStatusButton(
                                  icon: Icons.water,
                                  label: 'Medium',
                                  color: AppColors.partial,
                                  isSelected: _selectedVulnerability == 'medium',
                                  onTap: () => setState(() => _selectedVulnerability = 'medium'),
                                ),
                                const SizedBox(width: 8),
                                _CompactStatusButton(
                                  icon: Icons.flood,
                                  label: 'High',
                                  color: AppColors.notPassable,
                                  isSelected: _selectedVulnerability == 'high',
                                  onTap: () => setState(() => _selectedVulnerability = 'high'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _notesController,
                              maxLines: 2, // slightly bigger since it's hidden
                              style: GoogleFonts.inter(fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Add contextual notes...',
                                hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant),
                                fillColor: AppColors.surfaceContainerLowest,
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                // Change Summary
                if (statusChanged || vulnChanged) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sync_alt_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            [
                              if (statusChanged) '${_formatStatus(selectedRoad!.status)} → ${_formatStatus(_selectedStatus)}',
                              if (vulnChanged) 'vulnerability: ${selectedRoad!.vulnerability} → $_selectedVulnerability',
                            ].join(' • '),
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Action row
                Row(
                  children: [
                    if (!_isMultiSelectMode && _selectedRoadId != null) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          onPressed: _deleteRoad,
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
                          tooltip: 'Delete Road',
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        onPressed: hasSelection ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.save_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _isMultiSelectMode
                                  ? 'Update ${_selectedRoadIds.length} Road${_selectedRoadIds.length != 1 ? 's' : ''}'
                                  : 'Save Changes',
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── INFO BANNER ──────────────────────────────────────────────────────

  Widget _buildInfoBanner(RoadStatus? selectedRoad) {
    if (_isMultiSelectMode) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.checklist_rounded, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(
              '${_selectedRoadIds.length} road${_selectedRoadIds.length != 1 ? 's' : ''} selected',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ],
        ),
      );
    }

    if (selectedRoad == null) return const SizedBox.shrink();

    final statusColor = _getStatusColor(selectedRoad.status);
    final pendingCount =
        AppStateService.instance.reports.where((r) => r.roadId == selectedRoad.id && r.status == 'pending').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedRoad.name,
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _formatStatus(selectedRoad.status),
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: statusColor),
                      ),
                      TextSpan(
                        text: ' • ${selectedRoad.riskCategory} • ${_getTimeAgo(selectedRoad.updatedAt)}',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant),
                      ),
                      if (pendingCount > 0)
                        TextSpan(
                          text: ' • $pendingCount report${pendingCount > 1 ? 's' : ''}',
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── LOADING OVERLAY ──────────────────────────────────────────────────

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                widget.reportIdToVerify != null ? 'Verifying...' : 'Updating...',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _TopCircleButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final String tooltip;

  const _TopCircleButton({required this.icon, required this.isActive, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppColors.primary : AppColors.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Icon(
            icon,
            size: 22,
            color: isActive ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? activeColor;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.primary;
    return Semantics(
      label: 'Filter by $label',
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              if (!isSelected)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
            ],
            border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.5) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? color : AppColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? color : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactStatusButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _CompactStatusButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: 'Set to $label',
        button: true,
        selected: isSelected,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.15) : AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
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
