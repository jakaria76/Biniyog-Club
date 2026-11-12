import 'package:flutter/material.dart';

/// Website er "quote" er motoi choto banner — emerald + gold
class QuoteBanner extends StatelessWidget {
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color goldLight = Color(0xFFD9BE8C);

  final String quote;
  final String quoteAuthor;
  final String? imageUrl; // purono call gulo jate compile kore — ekhon use hoy na

  const QuoteBanner({
    super.key,
    required this.quote,
    this.quoteAuthor = 'Biniyog Club',
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF125A43), emeraldDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Website er moto bam pashe sonali dag
            Container(width: 2, color: goldLight.withAlpha(170)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '“$quote”',
                    style: TextStyle(color: Colors.white.withAlpha(225), fontSize: 13.5, height: 1.45),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '— $quoteAuthor',
                    style: const TextStyle(color: goldLight, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}