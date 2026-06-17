import 'package:flutter/material.dart';
import 'user_metrics.dart';

class UserMetricsFormDialog extends StatefulWidget {
  const UserMetricsFormDialog({
    super.key,
    required this.initialMetrics,
    required this.onSave,
  });

  final UserMetrics? initialMetrics;
  final Function(UserMetrics) onSave;

  @override
  State<UserMetricsFormDialog> createState() => _UserMetricsFormDialogState();
}

class _UserMetricsFormDialogState extends State<UserMetricsFormDialog> {
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  late TextEditingController _ageController;
  late String _selectedGender;
  late bool _useMetricUnits;

  // Validation state
  String? _heightError;
  String? _weightError;
  String? _ageError;
  bool _isFormValid = true;

  // Constants for validation
  static const double MIN_HEIGHT_CM = 50.0;
  static const double MAX_HEIGHT_CM = 300.0;
  static const double MIN_WEIGHT_KG = 10.0;
  static const double MAX_WEIGHT_KG = 500.0;
  static const int MIN_AGE = 1;
  static const int MAX_AGE = 150;

  @override
  void initState() {
    super.initState();
    _useMetricUnits = true;
    _selectedGender = 'M';

    if (widget.initialMetrics != null) {
      _heightController = TextEditingController(
        text: widget.initialMetrics!.heightCm.toStringAsFixed(1),
      );
      _weightController = TextEditingController(
        text: widget.initialMetrics!.weightKg.toStringAsFixed(1),
      );
      _ageController = TextEditingController(
        text: widget.initialMetrics!.age.toString(),
      );
      _selectedGender = widget.initialMetrics!.gender;
    } else {
      _heightController = TextEditingController();
      _weightController = TextEditingController();
      _ageController = TextEditingController();
    }

    // Add listeners for real-time validation
    _heightController.addListener(_validateHeight);
    _weightController.addListener(_validateWeight);
    _ageController.addListener(_validateAge);
  }

  @override
  void dispose() {
    _heightController.removeListener(_validateHeight);
    _weightController.removeListener(_validateWeight);
    _ageController.removeListener(_validateAge);

    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  // Real-time validation methods
  void _validateHeight() {
    setState(() {
      final height = double.tryParse(_heightController.text);
      if (_heightController.text.isEmpty) {
        _heightError = 'Height is required';
      } else if (height == null) {
        _heightError = 'Please enter a valid number';
      } else {
        final heightInUnit = _useMetricUnits ? height : height * 2.54;
        if (heightInUnit < MIN_HEIGHT_CM) {
          _heightError =
              'Height must be at least ${_formatHeight(MIN_HEIGHT_CM)}';
        } else if (heightInUnit > MAX_HEIGHT_CM) {
          _heightError =
              'Height must be less than ${_formatHeight(MAX_HEIGHT_CM)}';
        } else {
          _heightError = null;
        }
      }
    });
  }

  void _validateWeight() {
    setState(() {
      final weight = double.tryParse(_weightController.text);
      if (_weightController.text.isEmpty) {
        _weightError = 'Weight is required';
      } else if (weight == null) {
        _weightError = 'Please enter a valid number';
      } else {
        final weightInKg = _useMetricUnits ? weight : weight * 0.453592;
        if (weightInKg < MIN_WEIGHT_KG) {
          _weightError =
              'Weight must be at least ${_formatWeight(MIN_WEIGHT_KG)}';
        } else if (weightInKg > MAX_WEIGHT_KG) {
          _weightError =
              'Weight must be less than ${_formatWeight(MAX_WEIGHT_KG)}';
        } else {
          _weightError = null;
        }
      }
    });
  }

  void _validateAge() {
    setState(() {
      final age = int.tryParse(_ageController.text);
      if (_ageController.text.isEmpty) {
        _ageError = 'Age is required';
      } else if (age == null) {
        _ageError = 'Please enter a valid age';
      } else if (age < MIN_AGE) {
        _ageError = 'Age must be at least $MIN_AGE';
      } else if (age > MAX_AGE) {
        _ageError = 'Age must be less than $MAX_AGE';
      } else {
        _ageError = null;
      }
    });
  }

  String _formatHeight(double heightCm) {
    if (_useMetricUnits) {
      return '${heightCm.toStringAsFixed(1)} cm';
    } else {
      return '${(heightCm / 2.54).toStringAsFixed(1)} inches';
    }
  }

  String _formatWeight(double weightKg) {
    if (_useMetricUnits) {
      return '${weightKg.toStringAsFixed(1)} kg';
    } else {
      return '${(weightKg / 0.453592).toStringAsFixed(1)} lbs';
    }
  }

  bool _validateForm() {
    _validateHeight();
    _validateWeight();
    _validateAge();

    return _heightError == null &&
        _weightError == null &&
        _ageError == null &&
        _selectedGender.isNotEmpty;
  }

  void _handleSave() {
    if (!_validateForm()) {
      setState(() {
        _isFormValid = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix all errors before saving'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Parse values after validation
    final height = double.parse(_heightController.text);
    final weight = double.parse(_weightController.text);
    final age = int.parse(_ageController.text);

    // Convert imperial to metric
    final heightCm = _useMetricUnits ? height : height * 2.54;
    final weightKg = _useMetricUnits ? weight : weight * 0.453592;

    final metrics = UserMetrics(
      heightCm: heightCm,
      weightKg: weightKg,
      age: age,
      gender: _selectedGender,
    );

    widget.onSave(metrics);
    Navigator.of(context).pop();
  }

  void _handleUnitToggle(bool useMetric) {
    if (useMetric == _useMetricUnits) return;

    // Convert current values when toggling units
    final currentHeight = double.tryParse(_heightController.text);
    final currentWeight = double.tryParse(_weightController.text);

    setState(() {
      _useMetricUnits = useMetric;
      _heightError = null;
      _weightError = null;

      // Update controllers to show converted values
      if (currentHeight != null) {
        final convertedHeight = useMetric
            ? currentHeight *
                  2.54 // inches to cm
            : currentHeight / 2.54; // cm to inches
        _heightController.text = convertedHeight.toStringAsFixed(1);
      }

      if (currentWeight != null) {
        final convertedWeight = useMetric
            ? currentWeight *
                  0.453592 // lbs to kg
            : currentWeight / 0.453592; // kg to lbs
        _weightController.text = convertedWeight.toStringAsFixed(1);
      }

      // Re-validate after unit change
      _validateHeight();
      _validateWeight();
    });
  }

  void _resetForm() {
    setState(() {
      _heightController.clear();
      _weightController.clear();
      _ageController.clear();
      _heightError = null;
      _weightError = null;
      _ageError = null;
      _isFormValid = true;

      if (widget.initialMetrics != null) {
        _heightController.text = widget.initialMetrics!.heightCm
            .toStringAsFixed(1);
        _weightController.text = widget.initialMetrics!.weightKg
            .toStringAsFixed(1);
        _ageController.text = widget.initialMetrics!.age.toString();
        _selectedGender = widget.initialMetrics!.gender;
      } else {
        _selectedGender = 'M';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Your Metrics')),
          if (widget.initialMetrics != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _resetForm,
              tooltip: 'Reset to original values',
            ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unit toggle
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Metric (cm, kg)'),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Imperial (in, lbs)'),
                  ),
                ],
                selected: {_useMetricUnits},
                onSelectionChanged: (Set<bool> newSelection) {
                  _handleUnitToggle(newSelection.first);
                },
              ),
            ),

            // Height field with error
            TextFormField(
              controller: _heightController,
              decoration: InputDecoration(
                labelText: 'Height (${_useMetricUnits ? 'cm' : 'inches'})',
                border: const OutlineInputBorder(),
                errorText: _heightError,
                isDense: true,
                suffixIcon: _heightController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _heightController.clear();
                          _validateHeight();
                        },
                        tooltip: 'Clear',
                      )
                    : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => _validateHeight(),
            ),
            const SizedBox(height: 12),

            // Weight field with error
            TextFormField(
              controller: _weightController,
              decoration: InputDecoration(
                labelText: 'Weight (${_useMetricUnits ? 'kg' : 'lbs'})',
                border: const OutlineInputBorder(),
                errorText: _weightError,
                isDense: true,
                suffixIcon: _weightController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _weightController.clear();
                          _validateWeight();
                        },
                        tooltip: 'Clear',
                      )
                    : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => _validateWeight(),
            ),
            const SizedBox(height: 12),

            // Age field with error
            TextFormField(
              controller: _ageController,
              decoration: InputDecoration(
                labelText: 'Age (years)',
                border: const OutlineInputBorder(),
                errorText: _ageError,
                isDense: true,
                suffixIcon: _ageController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _ageController.clear();
                          _validateAge();
                        },
                        tooltip: 'Clear',
                      )
                    : null,
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => _validateAge(),
            ),
            const SizedBox(height: 12),

            // Gender selection
            DropdownButtonFormField<String>(
              value: _selectedGender,
              decoration: const InputDecoration(
                labelText: 'Gender',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'M', child: Text('Male')),
                DropdownMenuItem(value: 'F', child: Text('Female')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedGender = value;
                  });
                }
              },
            ),

            if (!_isFormValid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Please fix all errors',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.initialMetrics != null)
          TextButton(onPressed: _resetForm, child: const Text('Reset')),
        ElevatedButton(onPressed: _handleSave, child: const Text('Save')),
      ],
    );
  }
}
