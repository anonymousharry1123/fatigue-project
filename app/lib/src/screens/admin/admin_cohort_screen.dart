import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_controller.dart';
import '../../synthetic/cohort_repository.dart';
import '../../synthetic/cohort_stats.dart';
import '../../synthetic/csv_loader.dart';
import '../../synthetic/synthetic_person.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import 'admin_charts.dart';
import 'admin_person_screen.dart';

class AdminCohortScreen extends StatefulWidget {
  const AdminCohortScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AdminCohortScreen> createState() => _AdminCohortScreenState();
}

class _AdminCohortScreenState extends State<AdminCohortScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<SyntheticPerson> _people = const [];
  CohortSummary? _summary;
  String? _status;
  String? _error;
  bool _busy = false;
  double _progress = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAsset() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Loading synthetic CSV…';
    });
    try {
      final people = await SyntheticCsvLoader.loadAsset();
      final summary = CohortStats.summarize(people);
      setState(() {
        _people = people;
        _summary = summary;
        _status = 'Loaded ${people.length} synthetic students from asset';
      });
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _recompute() async {
    if (_people.isEmpty) {
      await _loadAsset();
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Recomputing scores…';
    });
    try {
      final csv = await rootBundle.loadString(syntheticStudentsAssetPath);
      final people = SyntheticCsvLoader.parseCsv(csv);
      setState(() {
        _people = people;
        _summary = CohortStats.summarize(people);
        _status = 'Recomputed ${people.length} scores with FatigueEngine';
      });
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    if (!widget.controller.isCloudAuthenticated) {
      setState(
        () => _error =
            'Sign in with Firebase first (Profile → Cloud account) to publish.',
      );
      return;
    }
    if (_people.isEmpty) {
      setState(() => _error = 'Load the CSV asset before publishing.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _status = 'Publishing cohort to Firestore…';
    });
    try {
      final repo = SyntheticCohortRepository();
      await repo.publish(
        _people,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progress = done / total;
            _status = 'Published $done / $total students';
          });
        },
      );
      setState(() => _status = 'Published ${_people.length} synthetic users');
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _hydrate() async {
    if (!widget.controller.isCloudAuthenticated) {
      setState(
        () => _error = 'Sign in with Firebase first to hydrate from cloud.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Reading syntheticCohort/summary…';
    });
    try {
      final repo = SyntheticCohortRepository();
      final summary = await repo.readSummary();
      final people = await repo.readPeople(limit: 250);
      if (summary == null && people.isEmpty) {
        setState(() => _error = 'No published synthetic cohort found.');
        return;
      }
      setState(() {
        if (people.isNotEmpty) {
          _people = people;
          _summary = CohortStats.summarize(people);
        } else {
          _summary = summary;
        }
        _status = people.isEmpty
            ? 'Hydrated summary only (n=${summary?.n ?? 0})'
            : 'Hydrated ${people.length} published students';
      });
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _clearCloud() async {
    if (!widget.controller.isCloudAuthenticated) {
      setState(() => _error = 'Sign in with Firebase first to clear cloud data.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear published cohort?'),
        content: const Text(
          'This deletes syntheticUsers and syntheticCohort/summary. Real user accounts are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _status = 'Clearing published cohort…';
    });
    try {
      await SyntheticCohortRepository().clearPublished(
        onProgress: (done) {
          if (!mounted) return;
          setState(() => _status = 'Deleted $done synthetic users…');
        },
      );
      setState(() => _status = 'Published cohort cleared');
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _exportJson() async {
    if (_people.isEmpty) {
      setState(() => _error = 'Load the cohort before exporting.');
      return;
    }
    final payload = jsonEncode({
      'n': _people.length,
      'summary': _summary?.toCloud(),
      'people': _people.take(50).map((p) => p.toExportJson()).toList(),
      'note': 'Export includes the first 50 people for clipboard size.',
    });
    await Clipboard.setData(ClipboardData(text: payload));
    setState(() => _status = 'Copied scored JSON sample (50 people) to clipboard');
  }

  List<SyntheticPerson> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _people;
    return _people
        .where(
          (p) =>
              p.id.contains(q) ||
              p.gender.toLowerCase().contains(q) ||
              p.education.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      backgroundColor: TonyoColors.background,
      appBar: AppBar(
        title: const Text('Cohort Lab'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Relations'),
            Tab(text: 'People'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _busy ? null : _loadAsset,
                  child: const Text('Load CSV'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : _recompute,
                  child: const Text('Recompute'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : _publish,
                  child: const Text('Publish'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : _hydrate,
                  child: const Text('Hydrate'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : _exportJson,
                  child: const Text('Export'),
                ),
                TextButton(
                  onPressed: _busy ? null : _clearCloud,
                  child: const Text('Clear cloud'),
                ),
              ],
            ),
          ),
          if (_busy)
            LinearProgressIndicator(
              value: _progress > 0 && _progress < 1 ? _progress : null,
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _status!,
                  style: const TextStyle(
                    color: TonyoColors.mint,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: TonyoColors.coral,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(summary: summary),
                _RelationsTab(summary: summary),
                _PeopleTab(
                  people: _filtered,
                  onQuery: (value) => setState(() => _query = value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.summary});

  final CohortSummary? summary;

  @override
  Widget build(BuildContext context) {
    if (summary == null || summary!.n == 0) {
      return const Center(
        child: Text(
          'Load the synthetic CSV to see score distributions.',
          style: TextStyle(color: TonyoColors.muted),
          textAlign: TextAlign.center,
        ),
      );
    }
    final s = summary!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Row(
          children: [
            _StatCard('N', '${s.n}', TonyoColors.primary),
            const SizedBox(width: 8),
            _StatCard(
              'Energy',
              '${s.meanEnergy.toStringAsFixed(0)}',
              TonyoColors.mint,
              subtitle: 'median ${s.medianEnergy.toStringAsFixed(0)}',
            ),
            const SizedBox(width: 8),
            _StatCard(
              'Cognitive',
              '${s.meanCognitive.toStringAsFixed(0)}',
              TonyoColors.blue,
              subtitle: 'median ${s.medianCognitive.toStringAsFixed(0)}',
            ),
          ],
        ),
        const SectionHeader('Energy distribution'),
        TonyoCard(
          child: CohortHistogramChart(
            bins: s.energyHistogram,
            color: TonyoColors.mint,
          ),
        ),
        const SectionHeader('Cognitive distribution'),
        TonyoCard(
          child: CohortHistogramChart(
            bins: s.cognitiveHistogram,
            color: TonyoColors.blue,
          ),
        ),
        const SectionHeader('By education'),
        TonyoCard(
          child: CohortGroupBars(
            groups: s.byEducation,
            valueOf: (g) => g.meanEnergy,
            color: TonyoColors.violet,
          ),
        ),
        const SectionHeader('By gender'),
        TonyoCard(
          child: CohortGroupBars(
            groups: s.byGender,
            valueOf: (g) => g.meanCognitive,
            color: TonyoColors.amber,
          ),
        ),
      ],
    );
  }
}

class _RelationsTab extends StatelessWidget {
  const _RelationsTab({required this.summary});

  final CohortSummary? summary;

  @override
  Widget build(BuildContext context) {
    if (summary == null || summary!.n == 0) {
      return const Center(
        child: Text(
          'Load the cohort to explore signal vs score relationships.',
          style: TextStyle(color: TonyoColors.muted),
        ),
      );
    }
    final s = summary!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        TonyoCard(
          child: CohortScatterChart(
            points: s.sleepVsEnergy,
            xLabel: 'Sleep (hr)',
            yLabel: 'Energy',
            color: TonyoColors.mint,
          ),
        ),
        const SizedBox(height: 12),
        TonyoCard(
          child: CohortScatterChart(
            points: s.screenVsCognitive,
            xLabel: 'Screen+social (hr)',
            yLabel: 'Cognitive',
            color: TonyoColors.violet,
          ),
        ),
        const SizedBox(height: 12),
        TonyoCard(
          child: CohortScatterChart(
            points: s.studyVsCognitive,
            xLabel: 'Study (hr)',
            yLabel: 'Cognitive',
            color: TonyoColors.blue,
          ),
        ),
        const SizedBox(height: 12),
        TonyoCard(
          child: CohortScatterChart(
            points: s.exerciseVsEnergy,
            xLabel: 'Exercise daily (hr)',
            yLabel: 'Energy',
            color: TonyoColors.coral,
          ),
        ),
        const SizedBox(height: 12),
        TonyoCard(
          child: CohortScatterChart(
            points: s.caffeineVsEnergy,
            xLabel: 'Caffeine (drinks)',
            yLabel: 'Energy',
            color: TonyoColors.amber,
          ),
        ),
      ],
    );
  }
}

class _PeopleTab extends StatelessWidget {
  const _PeopleTab({
    required this.people,
    required this.onQuery,
  });

  final List<SyntheticPerson> people;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: onQuery,
            decoration: const InputDecoration(
              hintText: 'Search id, gender, education',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: people.isEmpty
              ? const Center(
                  child: Text(
                    'No people loaded',
                    style: TextStyle(color: TonyoColors.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  itemCount: people.length.clamp(0, 500),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final person = people[index];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AdminPersonScreen(person: person),
                          ),
                        ),
                        child: TonyoCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Synthetic ${person.id}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      '${person.age} · ${person.gender} · ${person.education}',
                                      style: const TextStyle(
                                        color: TonyoColors.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'E ${person.score.energy}',
                                style: const TextStyle(
                                  color: TonyoColors.mint,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'C ${person.score.cognitive}',
                                style: const TextStyle(
                                  color: TonyoColors.blue,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
    this.label,
    this.value,
    this.color, {
    this.subtitle,
  });

  final String label;
  final String value;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TonyoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(color: TonyoColors.muted, fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }
}
