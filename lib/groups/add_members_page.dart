import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/groups/group_repository.dart';

class AddMembersPage extends StatefulWidget {
  const AddMembersPage({
    super.key,
    required this.groupId,
    required this.currentMemberIds,
  });

  final String groupId;
  final List<String> currentMemberIds;

  @override
  State<AddMembersPage> createState() => _AddMembersPageState();
}

class _AddMembersPageState extends State<AddMembersPage> {
  final GroupRepository _repo = GroupRepository();
  final TextEditingController _searchController = TextEditingController();
  
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;
  final Set<String> _addingIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (_searchQuery == query) return;
    
    setState(() {
      _searchQuery = query;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _repo.searchUsersByPrefix(prefix: query);
      if (mounted && _searchQuery == query) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _addMember(String userId) async {
    if (_addingIds.contains(userId)) return;

    setState(() => _addingIds.add(userId));

    try {
      await _repo.addMemberToGroup(groupId: widget.groupId, userId: userId);
      
      if (mounted) {
        // Technically, we should add to widget.currentMemberIds so it immediately updates UI,
        // but `widget` fields are final. We'll just rely on the stream in the parent page to update it.
        // For visual feedback here, we can temporarily add it to a local copy if we want,
        // but pop-ing back or just changing button to "Added" works.
        widget.currentMemberIds.add(userId); // Since it's a list reference, this mutates the original list.
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add user: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _addingIds.remove(userId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Members'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                hintText: 'Search username...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) {
      return Center(
        child: Text(
          'Type a username to find people.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('No users found.', style: TextStyle(color: Colors.black54)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final id = user['id'] as String;
        final displayName = user['displayName'] as String? ?? 'Athlete';
        final username = user['username'] as String? ?? id.substring(0, 6);

        final isAlreadyMember = widget.currentMemberIds.contains(id);
        final isAdding = _addingIds.contains(id);

        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: kBrandOrange,
              foregroundColor: Colors.white,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('@$username'),
            trailing: isAlreadyMember
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Added', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  )
                : FilledButton(
                    onPressed: isAdding ? null : () => _addMember(id),
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrandOrange,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: isAdding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Add'),
                  ),
          ),
        );
      },
    );
  }
}
