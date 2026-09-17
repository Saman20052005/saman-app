import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_shadows.dart';
import '../../data/models/exercise.dart';

class ExerciseVideoPlayer extends StatelessWidget {
  final Exercise exercise;

  const ExerciseVideoPlayer({super.key, required this.exercise});

  Future<void> _launchYouTube() async {
    if (exercise.youtubeVideoId == null) return;
    final url =
        Uri.parse('https://www.youtube.com/watch?v=${exercise.youtubeVideoId}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'exercise_${exercise.slug}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: exercise.thumbnailUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.grey[300]),
            errorWidget: (_, __, ___) => Container(
              color: Colors.grey[300],
              child: const Icon(Icons.fitness_center,
                  size: 80, color: Colors.grey),
            ),
          ),
          // Gradient overlay
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
          ),
          // Play button (only if youtube video id exists)
          if (exercise.youtubeVideoId != null)
            Center(
              child: GestureDetector(
                onTap: _launchYouTube,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [AppShadows.medium],
                  ),
                  child: const Icon(Icons.play_arrow,
                      size: 36, color: Colors.black),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
