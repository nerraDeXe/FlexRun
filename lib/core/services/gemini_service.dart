import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  Future<String> analyzeRun(Map<String, dynamic> sessionData) async {
    if (_apiKey.isEmpty) {
      throw Exception('Gemini API key is not configured.');
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey,
        requestOptions: const RequestOptions(apiVersion: 'v1'),
      );

      final distanceKm =
          ((sessionData['distanceMeters'] as num?)?.toDouble() ?? 0) / 1000;
      final calories = (sessionData['caloriesKcal'] as num?)?.toDouble() ?? 0;
      final elevation =
          (sessionData['elevationGainMeters'] as num?)?.toDouble() ?? 0;
      final durationSeconds =
          (sessionData['activeDurationSeconds'] as num?)?.toInt() ?? 0;
      final maxSpeed = (sessionData['maxSpeedMps'] as num?)?.toDouble();

      String paceLabel = '--:--';
      if (durationSeconds > 0 && distanceKm > 0) {
        final secondsPerKm = durationSeconds / distanceKm;
        final minutes = (secondsPerKm / 60).floor();
        final seconds = (secondsPerKm % 60).round();
        paceLabel = '$minutes:${seconds.toString().padLeft(2, '0')} min/km';
      }

      String maxSpeedLabel = 'N/A';
      if (maxSpeed != null && maxSpeed > 0) {
        final speedKmh = maxSpeed * 3.6;
        maxSpeedLabel = '${speedKmh.toStringAsFixed(1)} km/h';
      }

      final prompt =
          '''
You are an encouraging, yet honest running coach providing a short analysis of a runner's recent workout.
Here are the workout stats:
- Distance: ${distanceKm.toStringAsFixed(2)} km
- Duration: ${durationSeconds ~/ 60} minutes and ${durationSeconds % 60} seconds
- Average Pace: $paceLabel
- Elevation Gain: ${elevation.toStringAsFixed(0)} m
- Calories Burned: ${calories.toStringAsFixed(0)} kcal
- Max Speed: $maxSpeedLabel

Based on these metrics, provide a short, single-paragraph analysis (maximum 3 sentences), preferbly with short sentences. 
Focus on what they did well, an interesting correlation (e.g. good pace despite elevation), and a quick word of encouragement.
Keep the tone energetic and premium, but not to the point of being patronising. Do not use markdown formatting (like bolding or lists).
''';

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      return response.text?.trim() ?? "Great effort! Keep up the good work.";
    } catch (e) {
      throw Exception('Unable to generate AI insights: $e');
    }
  }
}
