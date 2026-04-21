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

  @override
  void initState() {
    super.initState();
    _useMetricUnits = true;
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
      _selectedGender = 'M';
    }
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final height = double.tryParse(_heightController.text);
    final weight = double.tryParse(_weightController.text);
    final age = int.tryParse(_ageController.text);

    if (height == null || weight == null || age == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields with valid numbers'),
        ),
      );
      return;
    }

    if (height <= 0 || weight <= 0 || age <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Height, weight, and age must be greater than 0'),
        ),
      );
      return;
    }

    // Convert imperial to metric if needed
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your Metrics'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unit toggle
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Expanded(
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
                        setState(() {
                          _useMetricUnits = newSelection.first;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Height field
            TextFormField(
              controller: _heightController,
              decoration: InputDecoration(
                labelText: 'Height (${_useMetricUnits ? 'cm' : 'inches'})',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            // Weight field
            TextFormField(
              controller: _weightController,
              decoration: InputDecoration(
                labelText: 'Weight (${_useMetricUnits ? 'kg' : 'lbs'})',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            // Age field
            TextFormField(
              controller: _ageController,
              decoration: const InputDecoration(
                labelText: 'Age (years)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            // Gender selection
            DropdownButtonFormField<String>(
              initialValue: _selectedGender,
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _handleSave, child: const Text('Save')),
      ],
    );
  }
}
