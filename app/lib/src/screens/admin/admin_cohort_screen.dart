import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _baselinePrefsKey = 'tonyo_cohort_relations_baseline_v1';

  late final TabController _tabs;
  List<SyntheticPerson> _people = const [];
  CohortSummary? _summary;
  CohortSummary? _baselineSummary;
  String? _status;
  String? _error;
  bool _busy = false;
  double _progress = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _restoreBaseline();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _restoreBaseline() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_baselinePrefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final baseline = CohortSummary.fromCloud(
        Map<String, dynamic>.from(decoded),
      );
      if (!mounted) return;
      setState(() => _baselineSummary = baseline);
    } catch (_) {
      // Ignore corrupt baseline freeze.
    }
  }

  Future<void> _freezeBaseline() async {
    final summary = _summary;
    if (summary == null || summary.n == 0) {
      setState(() => _error = 'Load/Recompute the cohort before freezing.');
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _baselinePrefsKey,
      jsonEncode(summary.toBaselineJson()),
    );
    if (!mounted) return;
    setState(() {
      _baselineSummary = summary;
      _error = null;
      _status =
          'Frozen Relations baseline · E ${summary.meanEnergy.toStringAsFixed(0)} / '
          'C ${summary.meanCognitive.toStringAsFixed(0)} '
          '(survives hot restart)';
    });
  }

  Future<void> _clearBaseline() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_baselinePrefsKey);
    if (!mounted) return;
    setState(() {
      _baselineSummary = null;
      _status = 'Cleared Relations baseline';
    });
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
                  onPressed: _busy || _summary == null ? null : _freezeBaseline,
                  child: const Text('Freeze baseline'),
                ),
                TextButton(
                  onPressed: _busy || _baselineSummary == null
                      ? null
                      : _clearBaseline,
                  child: const Text('Clear baseline'),
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
                _OverviewTab(summary: summary, baseline: _baselineSummary),
                _RelationsTab(summary: summary, baseline: _baselineSummary),
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

enum _PeopleSort {
  idAsc,
  energyLow,
  energyHigh,
  cognitiveLow,
  cognitiveHigh,
  sleepLow,
  sleepHigh,
  screenHigh,
  caffeineHigh,
  studyHigh,
  stressHigh,
}

extension on _PeopleSort {
  String get label => switch (this) {
    _PeopleSort.idAsc => 'ID ↑',
    _PeopleSort.energyLow => 'Energy ↑ low',
    _PeopleSort.energyHigh => 'Energy ↓ high',
    _PeopleSort.cognitiveLow => 'Cognitive ↑ low',
    _PeopleSort.cognitiveHigh => 'Cognitive ↓ high',
    _PeopleSort.sleepLow => 'Sleep ↑ low',
    _PeopleSort.sleepHigh => 'Sleep ↓ high',
    _PeopleSort.screenHigh => 'Screen ↓ high',
    _PeopleSort.caffeineHigh => 'Caffeine ↓ high',
    _PeopleSort.studyHigh => 'Study ↓ high',
    _PeopleSort.stressHigh => 'Stress ↓ high',
  };
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.summary, this.baseline});

  final CohortSummary? summary;
  final CohortSummary? baseline;

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
    final b = baseline;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        if (b != null && b.n > 0) ...[
          TonyoCard(
            child: Text(
              'Baseline freeze · Energy ${b.meanEnergy.toStringAsFixed(0)}'
              ' (med ${b.medianEnergy.toStringAsFixed(0)}) → '
              '${s.meanEnergy.toStringAsFixed(0)}'
              ' (med ${s.medianEnergy.toStringAsFixed(0)}) · '
              'Cognitive ${b.meanCognitive.toStringAsFixed(0)}'
              ' (med ${b.medianCognitive.toStringAsFixed(0)}) → '
              '${s.meanCognitive.toStringAsFixed(0)}'
              ' (med ${s.medianCognitive.toStringAsFixed(0)})',
              style: const TextStyle(
                color: TonyoColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            _StatCard('N', '${s.n}', TonyoColors.primary),
            const SizedBox(width: 8),
            _StatCard(
              'Energy',
              s.meanEnergy.toStringAsFixed(0),
              TonyoColors.mint,
              subtitle: 'median ${s.medianEnergy.toStringAsFixed(0)}',
            ),
            const SizedBox(width: 8),
            _StatCard(
              'Cognitive',
              s.meanCognitive.toStringAsFixed(0),
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
  const _RelationsTab({required this.summary, this.baseline});

  final CohortSummary? summary;
  final CohortSummary? baseline;

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
    final b = baseline;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        if (b != null && b.n > 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Before = frozen baseline · After = live Recompute. '
              'Axes share the same scale for each pair.',
              style: TextStyle(color: TonyoColors.muted, fontSize: 11),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Tip: Freeze baseline, edit FatigueEngine, hot restart, '
              'Recompute — then compare Before/After here.',
              style: TextStyle(color: TonyoColors.muted, fontSize: 11),
            ),
          ),
        _RelationCompareCard(
          live: s.sleepVsEnergy,
          frozen: b?.sleepVsEnergy,
          xLabel: 'Sleep (hr)',
          yLabel: 'Energy',
          color: TonyoColors.mint,
        ),
        const SizedBox(height: 12),
        _RelationCompareCard(
          live: s.sleepVsCognitive,
          frozen: b?.sleepVsCognitive,
          xLabel: 'Sleep (hr)',
          yLabel: 'Cognitive',
          color: TonyoColors.blue,
        ),
        const SizedBox(height: 12),
        _RelationCompareCard(
          live: s.screenVsEnergy,
          frozen: b?.screenVsEnergy,
          xLabel: 'Screen+social (hr)',
          yLabel: 'Energy',
          color: TonyoColors.coral,
        ),
        const SizedBox(height: 12),
        _RelationCompareCard(
          live: s.screenVsCognitive,
          frozen: b?.screenVsCognitive,
          xLabel: 'Screen+social (hr)',
          yLabel: 'Cognitive',
          color: TonyoColors.violet,
        ),
        const SizedBox(height: 12),
        _RelationCompareCard(
          live: s.studyVsCognitive,
          frozen: b?.studyVsCognitive,
          xLabel: 'Study (hr)',
          yLabel: 'Cognitive',
          color: TonyoColors.blue,
        ),
        const SizedBox(height: 12),
        _RelationCompareCard(
          live: s.exerciseVsEnergy,
          frozen: b?.exerciseVsEnergy,
          xLabel: 'Exercise daily (hr)',
          yLabel: 'Energy',
          color: TonyoColors.coral,
        ),
        const SizedBox(height: 12),
        _RelationCompareCard(
          live: s.caffeineVsEnergy,
          frozen: b?.caffeineVsEnergy,
          xLabel: 'Caffeine (drinks)',
          yLabel: 'Energy',
          color: TonyoColors.amber,
        ),
      ],
    );
  }
}

class _RelationCompareCard extends StatelessWidget {
  const _RelationCompareCard({
    required this.live,
    required this.frozen,
    required this.xLabel,
    required this.yLabel,
    required this.color,
  });

  final List<CohortScatterPoint> live;
  final List<CohortScatterPoint>? frozen;
  final String xLabel;
  final String yLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final before = frozen;
    if (before == null || before.isEmpty) {
      return TonyoCard(
        child: CohortScatterChart(
          points: live,
          xLabel: xLabel,
          yLabel: yLabel,
          color: color,
        ),
      );
    }

    final domain = CohortScatterChart.sharedDomain(before, live);
    final charts = [
      CohortScatterChart(
        points: before,
        xLabel: xLabel,
        yLabel: yLabel,
        badge: 'Before',
        color: TonyoColors.muted,
        height: 170,
        fixedMinX: domain.minX,
        fixedMaxX: domain.maxX,
        fixedMinY: domain.minY,
        fixedMaxY: domain.maxY,
      ),
      CohortScatterChart(
        points: live,
        xLabel: xLabel,
        yLabel: yLabel,
        badge: 'After',
        color: color,
        height: 170,
        fixedMinX: domain.minX,
        fixedMaxX: domain.maxX,
        fixedMinY: domain.minY,
        fixedMaxY: domain.maxY,
      ),
    ];

    return TonyoCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              children: [
                charts[0],
                const SizedBox(height: 12),
                charts[1],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: charts[0]),
              const SizedBox(width: 12),
              Expanded(child: charts[1]),
            ],
          );
        },
      ),
    );
  }
}

class _PeopleTab extends StatefulWidget {
  const _PeopleTab({
    required this.people,
    required this.onQuery,
  });

  final List<SyntheticPerson> people;
  final ValueChanged<String> onQuery;

  @override
  State<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<_PeopleTab> {
  _PeopleSort _sort = _PeopleSort.energyLow;

  List<SyntheticPerson> get _sorted {
    final list = List<SyntheticPerson>.from(widget.people);
    int cmpNum(num a, num b) => a.compareTo(b);
    switch (_sort) {
      case _PeopleSort.idAsc:
        list.sort(
          (a, b) => cmpNum(int.tryParse(a.id) ?? 0, int.tryParse(b.id) ?? 0),
        );
      case _PeopleSort.energyLow:
        list.sort((a, b) => cmpNum(a.score.energy, b.score.energy));
      case _PeopleSort.energyHigh:
        list.sort((a, b) => cmpNum(b.score.energy, a.score.energy));
      case _PeopleSort.cognitiveLow:
        list.sort((a, b) => cmpNum(a.score.cognitive, b.score.cognitive));
      case _PeopleSort.cognitiveHigh:
        list.sort((a, b) => cmpNum(b.score.cognitive, a.score.cognitive));
      case _PeopleSort.sleepLow:
        list.sort((a, b) => cmpNum(a.avgSleepHours, b.avgSleepHours));
      case _PeopleSort.sleepHigh:
        list.sort((a, b) => cmpNum(b.avgSleepHours, a.avgSleepHours));
      case _PeopleSort.screenHigh:
        list.sort((a, b) => cmpNum(b.foldedScreenHours, a.foldedScreenHours));
      case _PeopleSort.caffeineHigh:
        list.sort((a, b) => cmpNum(b.caffeineDrinks, a.caffeineDrinks));
      case _PeopleSort.studyHigh:
        list.sort((a, b) => cmpNum(b.studyHours, a.studyHours));
      case _PeopleSort.stressHigh:
        list.sort((a, b) => cmpNum(b.stressLevel, a.stressLevel));
    }
    return list;
  }

  String _metricLine(SyntheticPerson person) {
    final base = '${person.age} · ${person.gender} · ${person.education}';
    final focus = switch (_sort) {
      _PeopleSort.sleepLow || _PeopleSort.sleepHigh =>
        'sleep ${person.avgSleepHours.toStringAsFixed(1)}h',
      _PeopleSort.screenHigh =>
        'screen ${person.foldedScreenHours.toStringAsFixed(1)}h',
      _PeopleSort.caffeineHigh =>
        'caffeine ${person.caffeineDrinks.toStringAsFixed(0)}',
      _PeopleSort.studyHigh =>
        'study ${person.studyHours.toStringAsFixed(1)}h',
      _PeopleSort.stressHigh =>
        'stress ${person.stressLevel.toStringAsFixed(0)}/10',
      _PeopleSort.cognitiveLow || _PeopleSort.cognitiveHigh =>
        'C ${person.score.cognitive}',
      _PeopleSort.energyLow ||
      _PeopleSort.energyHigh ||
      _PeopleSort.idAsc =>
        'E ${person.score.energy}',
    };
    return '$base · $focus';
  }

  @override
  Widget build(BuildContext context) {
    final people = _sorted;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            onChanged: widget.onQuery,
            decoration: const InputDecoration(
              hintText: 'Search id, gender, education',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              const Text(
                'Sort',
                style: TextStyle(color: TonyoColors.muted, fontSize: 11),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<_PeopleSort>(
                  initialValue: _sort,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    for (final sort in _PeopleSort.values)
                      DropdownMenuItem(
                        value: sort,
                        child: Text(
                          sort.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _sort = value);
                  },
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Open the first 3 rows as outlier spot-checks for this sort.',
              style: TextStyle(color: TonyoColors.muted, fontSize: 10),
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
                                      _metricLine(person),
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
