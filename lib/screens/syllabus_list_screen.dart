import 'package:flutter/material.dart';

import '../models/syllabus.dart';
import '../repositories/syllabus_repository.dart';
import '../services/api_service.dart';
import 'session_screen.dart';

class SyllabusListScreen extends StatefulWidget {
  const SyllabusListScreen({
    super.key,
    required this.repository,
    this.gradeFilter,
    this.preloaded,
  });

  final SyllabusRepository repository;

  /// When set, only syllabi for this grade are shown (and the title reads
  /// "Grade X Syllabi"). Leave null to list every syllabus.
  final String? gradeFilter;

  /// A result the caller already loaded (the grade picker loads once), so
  /// this screen can show it immediately instead of fetching again. Pull to
  /// refresh still reloads from the repository.
  final SyllabusLoadResult? preloaded;

  @override
  State<SyllabusListScreen> createState() => _SyllabusListScreenState();
}

class _SyllabusListScreenState extends State<SyllabusListScreen> {
  List<Syllabus> _syllabi = [];
  bool _loading = true;
  bool _fromCache = false;
  String? _error;
  String? _initializingSyllabusId;

  @override
  void initState() {
    super.initState();
    final preloaded = widget.preloaded;
    if (preloaded != null) {
      _applyResult(preloaded);
      _loading = false;
    } else {
      _load();
    }
  }

  /// Stores a load result, keeping only the selected grade when filtering.
  void _applyResult(SyllabusLoadResult result) {
    final grade = widget.gradeFilter;
    _syllabi = grade == null
        ? result.syllabi
        : result.syllabi.where((s) => s.grade == grade).toList();
    _fromCache = result.fromCache;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.repository.loadSyllabi();
      setState(() {
        _applyResult(result);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectSyllabus(Syllabus syllabus) async {
    setState(() => _initializingSyllabusId = syllabus.id);

    try {
      final result = await widget.repository.getOrCreateSession(syllabus);
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SessionScreen(
            sessionId: result.sessionId,
            syllabusId: result.syllabusId,
            syllabusTitle: result.syllabusTitle,
            apiService: widget.repository.apiService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start session: $e')),
      );
    } finally {
      if (mounted) setState(() => _initializingSyllabusId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.gradeFilter == null
              ? 'Select Syllabus'
              : 'Grade ${widget.gradeFilter} Syllabi',
        ),
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

    if (_syllabi.isEmpty) {
      return const Center(child: Text('No syllabi available yet.'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _syllabi.length + (_fromCache ? 1 : 0),
        itemBuilder: (context, index) {
          if (_fromCache && index == 0) {
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

          final syllabus = _syllabi[index - (_fromCache ? 1 : 0)];
          final isInitializing = _initializingSyllabusId == syllabus.id;

          return ListTile(
            title: Text(syllabus.title),
            subtitle: Text('${syllabus.subject} · Grade ${syllabus.grade}'),
            trailing: isInitializing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.chevron_right),
            enabled: _initializingSyllabusId == null,
            onTap: () => _selectSyllabus(syllabus),
          );
        },
      ),
    );
  }
}