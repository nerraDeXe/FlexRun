import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fake_strava/core/services/gemini_service.dart';
import 'package:fake_strava/core/ui_components.dart';

class AIInsightsSection extends StatefulWidget {
  const AIInsightsSection({
    super.key,
    required this.firestore,
    required this.sessionId,
    required this.sessionData,
    required this.isMine,
  });

  final FirebaseFirestore firestore;
  final String sessionId;
  final Map<String, dynamic> sessionData;
  final bool isMine;

  @override
  State<AIInsightsSection> createState() => _AIInsightsSectionState();
}

class _AIInsightsSectionState extends State<AIInsightsSection> {
  bool _isLoading = false;
  String? _localAnalysis;

  @override
  void initState() {
    super.initState();
    _localAnalysis = widget.sessionData['aiAnalysis'] as String?;
  }

  Future<void> _generateInsights() async {
    setState(() => _isLoading = true);
    try {
      final gemini = GeminiService();
      final analysis = await gemini.analyzeRun(widget.sessionData);
      await widget.firestore.collection('tracking_sessions').doc(widget.sessionId).update({
        'aiAnalysis': analysis,
      });
      if (mounted) {
        setState(() {
          _localAnalysis = analysis;
        });
      }
    } catch (e) {
      if (mounted) {
        AppNotification.show(
          context: context,
          message: 'Failed to generate insights: $e',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiAnalysisRaw = _localAnalysis;
    final bool isErrorString = aiAnalysisRaw != null && 
        (aiAnalysisRaw.contains('AI insights are unavailable') || 
         aiAnalysisRaw.contains('Unable to generate AI insights'));

    final aiAnalysis = isErrorString ? null : aiAnalysisRaw;

    if (aiAnalysis != null && aiAnalysis.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFED7AA), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF97316).withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Gemini Insights',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9A3412),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              aiAnalysis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF7C2D12),
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (!widget.isMine) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _generateInsights,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFFF8FAFC), Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFF97316)),
                  )
                else
                  const Icon(Icons.auto_awesome, size: 18, color: Color(0xFFF97316)),
                const SizedBox(width: 8),
                Text(
                  _isLoading ? 'Analyzing run...' : 'Generate AI Insights',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
