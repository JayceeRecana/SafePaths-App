import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_strings.dart';
import '../../services/cached_road_reader.dart';
import '../../widgets/app_top_bar.dart';

class SavedRoadsScreen extends StatefulWidget {
  final Future<CachedRoadSnapshot> Function()? loader;
  const SavedRoadsScreen({super.key, this.loader});
  @override
  State<SavedRoadsScreen> createState() => _SavedRoadsScreenState();
}

class _SavedRoadsScreenState extends State<SavedRoadsScreen> {
  late Future<CachedRoadSnapshot> _saved;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _saved = (widget.loader ?? CachedRoadReader.load)();
  }

  String _date(BuildContext context, DateTime date) => DateFormat.yMMMd(
    Localizations.localeOf(context).toLanguageTag(),
  ).addPattern('h:mm a').format(date);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(
      title: tr(context, 'Saved roads'),
      showBackButton: true,
      showProfile: false,
      showSettingsAction: false,
    ),
    body: FutureBuilder<CachedRoadSnapshot>(
      future: _saved,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: Text(tr(context, 'Loading saved roads…')));
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(
                      context,
                      'Saved roads could not be read. Return to the account screen to check your session or connection.',
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_reload),
                    child: Text(tr(context, 'Retry')),
                  ),
                ],
              ),
            ),
          );
        }
        final saved = snapshot.data!;
        final roads =
            saved.roads
                .where((road) => road.name.toLowerCase().contains(_query))
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        tr(
                          context,
                          'Saved information only. Present road conditions are unconfirmed. Routing and reporting require an online account check.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      saved.lastSync == null
                          ? tr(
                              context,
                              'Road data has not been confirmed online.',
                            )
                          : '${tr(context, 'Roads last synced')}: ${_date(context, saved.lastSync!)}',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        labelText: tr(context, 'Search roads...'),
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                    ),
                  ],
                ),
              ),
            ),
            if (roads.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    tr(
                      context,
                      saved.roads.isEmpty
                          ? 'No saved roads are available on this phone. Connect to load road data.'
                          : 'No roads match your search.',
                    ),
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: roads.length,
              itemBuilder: (context, index) {
                final road = roads[index];
                final status = switch (road.status) {
                  'passable' => 'Passable',
                  'partial' => 'Partially passable',
                  'not_passable' => 'Not passable',
                  _ => 'Unconfirmed',
                };
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          road.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${tr(context, 'Last recorded status')}: ${tr(context, status)}',
                        ),
                        Text(
                          '${tr(context, 'Last recorded update')}: ${_date(context, road.updatedAt)}',
                        ),
                        if (road.notes.isNotEmpty) Text(road.notes),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    ),
  );
}
