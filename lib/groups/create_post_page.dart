import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/groups/group_repository.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({
    super.key,
    required this.groupId,
    required this.creatorId,
  });

  final String groupId;
  final String creatorId;

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final _repository = GroupRepository();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final FocusNode _locationFocusNode = FocusNode();
  bool _isUpcomingRun = false;
  DateTime? _scheduledTime;
  LatLng? _selectedLocation;
  LatLng? _currentLocation;
  final MapController _mapController = MapController();
  bool _isLoading = false;

  Timer? _debounceTimer;
  List<dynamic> _searchResults = [];
  bool _isSearching = false;


  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition({bool moveMap = false}) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      if (moveMap) {
        _mapController.move(_currentLocation!, 14.0);
      }
    }
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;

    setState(() {
      _scheduledTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _isUpcomingRun = true;
    });
  }

  Future<void> _submit() async {
    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a description')),
      );
      return;
    }

    if (_isUpcomingRun && _scheduledTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a scheduled time for the run')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Create post
      await _repository.createPost(
        groupId: widget.groupId,
        creatorId: widget.creatorId,
        description: _descriptionController.text,
        scheduledTime: _isUpcomingRun ? _scheduledTime : null,
        location: _isUpcomingRun ? _locationController.text : null,
        locationLat: _isUpcomingRun ? _selectedLocation?.latitude : null,
        locationLng: _isUpcomingRun ? _selectedLocation?.longitude : null,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating post: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    final client = HttpClient();
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '5',
        'addressdetails': '1',
      });
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'FlexRun-App-V1');
      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final List<dynamic> data = json.decode(responseBody);
        if (mounted) {
          setState(() {
            _searchResults = data;
            _isSearching = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error searching location: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    } finally {
      client.close();
    }
  }

  void _onLocationChanged(String val) {
    setState(() {}); // Rebuild to update clear button visibility
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _searchLocation(val);
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _locationController.dispose();
    _locationFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Post'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('POST', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: kBrandOrange,
                child: Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'What do you want to share?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(
              hintText: 'Share an upcoming run or some thoughts...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Is this an upcoming run?'),
            subtitle: const Text('Schedule a run for others to join'),
            value: _isUpcomingRun,
            onChanged: (val) => setState(() => _isUpcomingRun = val),
            activeThumbColor: kBrandOrange,
          ),
          if (_isUpcomingRun) ...[
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.calendar_today, color: kBrandOrange),
              title: Text(
                _scheduledTime == null
                    ? 'Select Date & Time'
                    : DateFormat('EEE, MMM d, y - h:mm a').format(_scheduledTime!),
              ),
              onTap: _selectDateTime,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Tap the map to set meeting point', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))
                ]
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentLocation ?? const LatLng(51.5, -0.09),
                        initialZoom: 13.0,
                        onTap: (tapPosition, point) {
                          setState(() {
                            _selectedLocation = point;
                            _searchResults = [];
                          });
                          _locationFocusNode.unfocus();
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: kMapThemeRasterHdPreview.urlTemplate,
                          subdomains: kMapThemeRasterHdPreview.subdomains,
                          userAgentPackageName: 'com.company.fakestrava',
                          retinaMode: RetinaMode.isHighDensity(context),
                        ),
                        if (_selectedLocation != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _selectedLocation!,
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.location_pin, color: kBrandOrange, size: 40),
                              ),
                            ],
                          ),
                      ],
                    ),
                    // Floating Search Bar overlay
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 2))
                          ],
                        ),
                        child: TextField(
                          controller: _locationController,
                          focusNode: _locationFocusNode,
                          onChanged: _onLocationChanged,
                          onSubmitted: _searchLocation,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            labelText: 'Location Name (Search or Type)',
                            prefixIcon: const Icon(Icons.location_on, color: kBrandOrange),
                            suffixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(kBrandOrange),
                                      ),
                                    ),
                                  )
                                : (_locationController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                                        onPressed: () {
                                          _locationController.clear();
                                          setState(() {
                                            _searchResults = [];
                                            _selectedLocation = null;
                                          });
                                        },
                                      )
                                    : null),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    // Search results suggestions dropdown
                    if (_searchResults.isNotEmpty)
                      Positioned(
                        top: 72,
                        left: 12,
                        right: 12,
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.98),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: _searchResults.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: Colors.grey.shade100,
                              ),
                              itemBuilder: (context, index) {
                                final item = _searchResults[index];
                                final displayName = item['display_name'] ?? '';
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      final latStr = item['lat'];
                                      final lonStr = item['lon'];
                                      if (latStr != null && lonStr != null) {
                                        final lat = double.tryParse(latStr);
                                        final lon = double.tryParse(lonStr);
                                        if (lat != null && lon != null) {
                                          setState(() {
                                            _selectedLocation = LatLng(lat, lon);
                                            _locationController.text = displayName;
                                            _searchResults = [];
                                          });
                                          _mapController.move(_selectedLocation!, 14.0);
                                          _locationFocusNode.unfocus();
                                        }
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            color: kBrandOrange,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              displayName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade800,
                                                fontWeight: FontWeight.w500,
                                              ),
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
                        ),
                      ),
                    // Current Location Button
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'map_current_loc_btn',
                        backgroundColor: Colors.white,
                        onPressed: () {
                          if (_currentLocation != null) {
                            _mapController.move(_currentLocation!, 14.0);
                          } else {
                            _determinePosition(moveMap: true);
                          }
                        },
                        child: const Icon(Icons.my_location, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
