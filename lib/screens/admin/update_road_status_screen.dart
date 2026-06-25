import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import '../../widgets/app_map.dart';
import '../shared/full_screen_map_screen.dart';

class UpdateRoadStatusScreen extends StatefulWidget {
  final String? prefilledRoadId;
  final String? reportIdToVerify;
  final String? suggestedStatus;
  final bool isStandalone;
  final bool autoFocusSearch;

  const UpdateRoadStatusScreen({
    super.key,
    this.prefilledRoadId,
    this.reportIdToVerify,
    this.suggestedStatus,
    this.isStandalone = false,
    this.autoFocusSearch = false,
  });

  @override
  State<UpdateRoadStatusScreen> createState() => _UpdateRoadStatusScreenState();
}

class _UpdateRoadStatusScreenState extends State<UpdateRoadStatusScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _selectedRoadId;
  String _selectedStatus = 'passable';
  String _selectedVulnerability = 'low';
  final _notesController = TextEditingController();
  bool _isSubmitting = false;
  Map<String, dynamic>? _lastState;
  
  bool _isMultiSelectMode = false;
  Set<String> _selectedRoadIds = {};
  List<Map<String, dynamic>>? _lastMultiState;

  @override
  void initState() {
    super.initState();
    _selectedRoadId = widget.prefilledRoadId;
    
    if (_selectedRoadId != null) {
      final road = AppStateService.instance.roads.cast<RoadStatus?>().firstWhere(
        (r) => r?.id == _selectedRoadId, 
        orElse: () => null
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
  }

  @override
  void dispose() {
    _notesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

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
            orElse: () => null
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
            action: currentLastMultiState != null ? SnackBarAction(
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
            ) : null,
          ),
        );
      } else {
        final prevRoad = AppStateService.instance.roads.cast<RoadStatus?>().firstWhere(
          (r) => r?.id == _selectedRoadId,
          orElse: () => null
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
        
        final currentLastState = _lastState; // Capture for the closure
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Road status updated successfully.'),
            action: currentLastState != null ? SnackBarAction(
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
            ) : null,
          ),
        );
      }
      
      if (widget.isStandalone) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) Navigator.of(context).pop();
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
        content: const Text('Are you sure you want to permanently delete this road from the database?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    setState(() => _isSubmitting = true);
    try {
      await AppStateService.instance.deleteRoadStatus(_selectedRoadId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Road deleted.')));
        setState(() => _selectedRoadId = null);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _handleSingleSelection(String id, RoadStatus road) {
    setState(() {
      _selectedRoadId = id;
      _selectedStatus = road.status;
      _selectedVulnerability = road.vulnerability;
      _notesController.text = road.notes == 'Imported from OSM' ? '' : road.notes;
    });
  }

  void _handleMultiSelection(Set<String> ids) {
    setState(() {
      _selectedRoadIds = ids;
    });
  }

  void _handleModeChanged(bool isMulti) {
    setState(() {
      _isMultiSelectMode = isMulti;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: 'Update Road',
        showBackButton: widget.isStandalone,
        showProfile: false,
        showSettingsAction: false,
        onBackPressed: widget.isStandalone ? () {
          if (Navigator.canPop(context)) Navigator.pop(context);
        } : null,
      ),
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildMapPreview(),
                const SizedBox(height: 24),
                _RoadSelectorCard(
                  initialSelectedRoadId: widget.prefilledRoadId,
                  autoFocusSearch: widget.autoFocusSearch,
                  onSingleSelection: _handleSingleSelection,
                  onMultiSelection: _handleMultiSelection,
                  onModeChanged: _handleModeChanged,
                  isMultiSelectMode: _isMultiSelectMode,
                  selectedRoadIds: _selectedRoadIds,
                  selectedRoadId: _selectedRoadId,
                ),
                const SizedBox(height: 16),
                _buildStatusSection(),
                const SizedBox(height: 16),
                _buildVulnerabilitySection(),
                const SizedBox(height: 16),
                _buildNotesSection(),
                const SizedBox(height: 24),
                _buildActionRow(),
              ],
            ),
          ),
          if (_isSubmitting)
            Container(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(
                      widget.reportIdToVerify != null ? 'Verifying report...' : 'Updating road...',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROAD STATUS UPDATE',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Manage Road\nConditions',
          style: GoogleFonts.manrope(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: AppColors.onSurface,
            height: 1.15,
          ),
        ),
      ],
    );
  }

  Widget _buildMapPreview() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Interactive Route Monitor',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'LIVE MAP',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FullScreenMapScreen()),
            );
          },
          child: Container(
            height: 300,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: AppColors.surfaceContainer,
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: const AbsorbPointer(
                    child: AppMap(showSearchButton: false),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Tooltip(
                    message: 'Expand map',
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const FullScreenMapScreen()),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.15)),
                        ),
                        child: const Icon(Icons.fullscreen_rounded, color: AppColors.primary, size: 24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSection() {
    final selectedRoadObj = AppStateService.instance.roads.cast<RoadStatus?>().firstWhere((r) => r?.id == _selectedRoadId, orElse: () => null);
    final hasGeometry = selectedRoadObj?.geometry != null && selectedRoadObj!.geometry!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SET STATUS',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatusButton(
                icon: Icons.check_circle,
                label: 'Passable',
                color: AppColors.secondary,
                isSelected: _selectedStatus == 'passable',
                onTap: () => setState(() => _selectedStatus = 'passable'),
              ),
              const SizedBox(width: 12),
              _StatusButton(
                icon: Icons.info,
                label: 'Partial',
                color: AppColors.partial,
                isSelected: _selectedStatus == 'partial',
                onTap: () => setState(() => _selectedStatus = 'partial'),
              ),
              const SizedBox(width: 12),
              _StatusButton(
                icon: Icons.warning,
                label: 'Impassable',
                color: AppColors.notPassable,
                isSelected: _selectedStatus == 'not_passable',
                onTap: () => setState(() => _selectedStatus = 'not_passable'),
              ),
            ],
          ),
          if (!hasGeometry && !_isMultiSelectMode) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This road has no geometry data. Status updates will save but won\'t appear visually on the map until geometry is added.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.orange[800],
                        height: 1.4,
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

  Widget _buildVulnerabilitySection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FLOOD VULNERABILITY',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Set this road's topographical flood risk for the Predictive Risk Model.",
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatusButton(
                icon: Icons.terrain,
                label: 'Low',
                color: AppColors.secondary,
                isSelected: _selectedVulnerability == 'low',
                onTap: () => setState(() => _selectedVulnerability = 'low'),
              ),
              const SizedBox(width: 12),
              _StatusButton(
                icon: Icons.water,
                label: 'Medium',
                color: AppColors.partial,
                isSelected: _selectedVulnerability == 'medium',
                onTap: () => setState(() => _selectedVulnerability = 'medium'),
              ),
              const SizedBox(width: 12),
              _StatusButton(
                icon: Icons.flood,
                label: 'High',
                color: AppColors.notPassable,
                isSelected: _selectedVulnerability == 'high',
                onTap: () => setState(() => _selectedVulnerability = 'high'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NOTES (OPTIONAL)',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add details about the road condition...',
              fillColor: AppColors.surface,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    final canSubmit = _isMultiSelectMode ? _selectedRoadIds.isNotEmpty : _selectedRoadId != null;
    return Row(
      children: [
        if (!_isMultiSelectMode && _selectedRoadId != null) ...[
          Container(
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              onPressed: _deleteRoad,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete Road',
            ),
          ),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: ElevatedButton(
            onPressed: canSubmit ? _submit : null,
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
                  _isMultiSelectMode ? 'Update ${_selectedRoadIds.length} Roads' : 'Update Road Status',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusButton({
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
        label: 'Set status to $label',
        button: true,
        selected: isSelected,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.1) : AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, size: 28, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
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

class _RoadSelectorCard extends StatefulWidget {
  final String? initialSelectedRoadId;
  final bool autoFocusSearch;
  final Function(String, RoadStatus) onSingleSelection;
  final Function(Set<String>) onMultiSelection;
  final Function(bool) onModeChanged;
  final bool isMultiSelectMode;
  final Set<String> selectedRoadIds;
  final String? selectedRoadId;

  const _RoadSelectorCard({
    required this.initialSelectedRoadId,
    required this.autoFocusSearch,
    required this.onSingleSelection,
    required this.onMultiSelection,
    required this.onModeChanged,
    required this.isMultiSelectMode,
    required this.selectedRoadIds,
    required this.selectedRoadId,
  });

  @override
  State<_RoadSelectorCard> createState() => _RoadSelectorCardState();
}

class _RoadSelectorCardState extends State<_RoadSelectorCard> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });

    if (widget.initialSelectedRoadId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final appState = AppStateService.instance;
        final roads = _applyFilters(appState.roads);
        if (roads.isNotEmpty) {
          widget.onSingleSelection(roads.first.id, roads.first);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RoadStatus> _applyFilters(List<RoadStatus> allRoads) {
    var roads = List.of(allRoads);
    if (_searchQuery.isNotEmpty) {
      roads = roads.where((r) => r.name.toLowerCase().contains(_searchQuery)).toList();
    }
    if (_filterStatus == 'affected') {
      roads = roads.where((r) => r.status == 'partial' || r.status == 'not_passable').toList();
    } else if (_filterStatus == 'vulnerable') {
      roads = roads.where((r) => r.vulnerability == 'high' || r.riskCategory == 'High').toList();
    } else if (_filterStatus == 'passable') {
      roads = roads.where((r) => r.status == 'passable').toList();
    } else if (_filterStatus == 'partial') {
      roads = roads.where((r) => r.status == 'partial').toList();
    } else if (_filterStatus == 'not_passable') {
      roads = roads.where((r) => r.status == 'not_passable').toList();
    } else if (_filterStatus == 'needs_update') {
      final now = DateTime.now();
      roads = roads.where((r) => now.difference(r.updatedAt).inHours >= 1).toList();
    }
    roads.sort((a, b) => a.name.compareTo(b.name));
    return roads;
  }

  Widget _buildFilterCard(String id, String label, IconData icon, {Color? activeColor}) {
    final isSelected = _filterStatus == id;
    final themeColor = activeColor ?? AppColors.primary;
    return Expanded(
      child: Semantics(
        label: 'Filter by $label',
        button: true,
        selected: isSelected,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _filterStatus = id;
            });
            final roads = _applyFilters(AppStateService.instance.roads);
            if (widget.isMultiSelectMode) {
              final visibleIds = roads.map((r) => r.id).toSet();
              final newSelection = widget.selectedRoadIds.intersection(visibleIds);
              if (newSelection.length != widget.selectedRoadIds.length || !newSelection.containsAll(widget.selectedRoadIds)) {
                widget.onMultiSelection(newSelection);
              }
            } else {
              if (roads.isNotEmpty) {
                final isCurrentlySelectedVisible = roads.any((r) => r.id == widget.selectedRoadId);
                if (!isCurrentlySelectedVisible) {
                  widget.onSingleSelection(roads.first.id, roads.first);
                }
              }
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected ? themeColor.withValues(alpha: 0.1) : AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? themeColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, size: 24, color: themeColor),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStateService.instance,
      builder: (context, _) {
        final roads = _applyFilters(AppStateService.instance.roads);

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SELECT ROAD',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  Semantics(
                    label: 'Toggle multi-select mode',
                    selected: widget.isMultiSelectMode,
                    button: true,
                    child: GestureDetector(
                      onTap: () {
                        widget.onModeChanged(!widget.isMultiSelectMode);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.isMultiSelectMode ? AppColors.primary : AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: widget.isMultiSelectMode ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.checklist,
                              size: 16,
                              color: widget.isMultiSelectMode ? Colors.white : AppColors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.isMultiSelectMode && widget.selectedRoadIds.isNotEmpty ? 'Multi-select (${widget.selectedRoadIds.length})' : 'Multi-select',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: widget.isMultiSelectMode ? FontWeight.w600 : FontWeight.w500,
                                color: widget.isMultiSelectMode ? Colors.white : AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                autofocus: widget.autoFocusSearch,
                decoration: InputDecoration(
                  hintText: 'Search roads...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.onSurfaceVariant),
                  suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear()) : null,
                  fillColor: AppColors.surface,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'QUICK FILTERS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildFilterCard('all', 'All Roads', Icons.list, activeColor: AppColors.primary),
                  const SizedBox(width: 8),
                  _buildFilterCard('needs_update', 'Needs Update', Icons.update, activeColor: Colors.orange),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'STATUS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildFilterCard('passable', 'Passable', Icons.check_circle, activeColor: AppColors.secondary),
                  const SizedBox(width: 8),
                  _buildFilterCard('partial', 'Partial', Icons.info, activeColor: AppColors.partial),
                  const SizedBox(width: 8),
                  _buildFilterCard('not_passable', 'Impassable', Icons.warning, activeColor: AppColors.notPassable),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'RISK & VULNERABILITY',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildFilterCard('affected', 'Affected (All)', Icons.warning_amber_rounded, activeColor: Colors.deepOrange),
                  const SizedBox(width: 8),
                  _buildFilterCard('vulnerable', 'Vulnerable', Icons.local_fire_department_outlined, activeColor: Colors.purple),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 16),
              SizedBox(
                height: 260,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: roads.length,
                  itemBuilder: (context, index) {
                    final road = roads[index];
                    final isSelected = widget.isMultiSelectMode 
                        ? widget.selectedRoadIds.contains(road.id)
                        : widget.selectedRoadId == road.id;
                    Color statusColor = AppColors.secondary;
                    if (road.status == 'partial') {
                      statusColor = AppColors.partial;
                    } else if (road.status == 'not_passable') {
                      statusColor = AppColors.notPassable;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Semantics(
                        label: '${road.name}, status: ${road.status}',
                        selected: isSelected,
                        button: true,
                        child: GestureDetector(
                          onTap: () {
                            if (widget.isMultiSelectMode) {
                              final newIds = Set<String>.from(widget.selectedRoadIds);
                              if (newIds.contains(road.id)) {
                                newIds.remove(road.id);
                              } else {
                                newIds.add(road.id);
                              }
                              widget.onMultiSelection(newIds);
                            } else {
                              widget.onSingleSelection(road.id, road);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent, width: 2),
                            ),
                            child: Row(
                              children: [
                                ExcludeSemantics(
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    road.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle, size: 20, color: AppColors.primary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
