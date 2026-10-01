import 'package:flutter/material.dart';

import '../tokens/motion.dart';
import 'media_art.dart';

/// Shows real media when there's a URL, fading it in over the placeholder art, and keeps the art if it fails. It
/// decodes at the size it's drawn, not the file's size, to save memory and keep scrolling smooth.
class OdMedia extends StatelessWidget {
  const OdMedia({super.key, required this.seed, this.url, this.child});

  final int seed;
  final String? url;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final art = OdMediaArt(seed: seed, child: child);
    if (url == null || url!.isEmpty) return art;
    return LayoutBuilder(
      builder: (context, box) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final width = box.maxWidth.isFinite
            ? (box.maxWidth * dpr).round()
            : null;
        return Stack(
          fit: StackFit.expand,
          children: [
            art,
            Image.network(
              url!,
              fit: BoxFit.cover,
              cacheWidth: width,
              gaplessPlayback: true,
              frameBuilder: (context, image, frame, sync) => AnimatedOpacity(
                opacity: sync || frame != null ? 1 : 0,
                duration: OdMotion.of(context, OdMotion.standard),
                child: image,
              ),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            ?child,
          ],
        );
      },
    );
  }
}
