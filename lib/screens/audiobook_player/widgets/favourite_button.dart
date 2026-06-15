import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/utils/app_logger.dart';

class FavouriteButton extends StatelessWidget {
  final Audiobook audiobook;
  final double size;
  final Color? color;

  const FavouriteButton({
    super.key,
    required this.audiobook,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('favourite_audiobooks_box').listenable(),
      builder: (context, Box box, widget) {
        final isFavourite = box.containsKey(audiobook.id);
        return IconButton(
          iconSize: size,
          icon: Icon(
            isFavourite ? Icons.favorite : Icons.favorite_border,
            color: isFavourite ? Colors.red : (color ?? Colors.white),
          ),
          onPressed: () {
            if (isFavourite) {
              box.delete(audiobook.id);
              AppLogger.debug('Removed from favourites: ${audiobook.title}');
            } else {
              box.put(audiobook.id, audiobook.toMap());
              AppLogger.debug('Added to favourites: ${audiobook.title}');
            }
          },
        );
      },
    );
  }
}
