import 'package:flutter/material.dart';

import '../repositories/syllabus_repository.dart';
import 'syllabus_list_screen.dart';

class GradeSelectScreen extends StatefulWidget {
  const GradeSelectScreen({super.key, required this.repository});

  final SyllabusRepository repository;

  @override
  State<GradeSelectScreen> createState() => _GradeSelectScreenState();
}

class _GradeSelectScreenState extends State<GradeSelectScreen> {
  SyllabusLoadResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.loadSyllabi();
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, int> _countByGrade() {
    final counts = <String, int>{};
    for (final s in _result!.syllabi) {
      counts[s.grade] = (counts[s.grade] ?? 0) + 1;
    }
    return counts;
  }

  /// Sorts numerically when grades are numbers (1, 2, 10 not 1, 10, 2),
  /// falls back to alphabetical for anything else.
  List<String> _sortedGrades(Iterable<String> grades) {
    final list = grades.toList();
    list.sort((a, b) {
      final na = int.tryParse(a);
      final nb = int.tryParse(b);
      if (na != null && nb != null) return na.compareTo(nb);
      return a.compareTo(b);
    });
    return list;
  }

  void _selectGrade(String grade) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SyllabusListScreen(
          repository: widget.repository,
          gradeFilter: grade,
          // Already loaded here — avoids a second network/cache fetch.
          preloaded: _result,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Grade'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final counts = _countByGrade();
    final grades = _sortedGrades(counts.keys);

    if (grades.isEmpty) {
      return const Center(child: Text('No syllabi available yet.'));
    }

    final fromCache = _result!.fromCache;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: grades.length + (fromCache ? 1 : 0),
        itemBuilder: (context, index) {
          if (fromCache && index == 0) {
            return Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: const Text(
                'Showing cached syllabi — pull to refresh when back online.',
                style: TextStyle(fontSize: 12),
              ),
            );
          }

          final grade = grades[index - (fromCache ? 1 : 0)];
          final count = counts[grade]!;

          return ListTile(
            leading: CircleAvatar(child: Text(grade)),
            title: Text('Grade $grade'),
            subtitle: Text('$count syllabus${count == 1 ? '' : 'es'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _selectGrade(grade),
          );
        },
      ),
    );
  }
}