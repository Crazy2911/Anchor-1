import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api_feed_repository.dart';
import 'app_state.dart';
import 'models.dart';

class CommunityPostImage extends StatefulWidget {
  final CommunityPost post;

  const CommunityPostImage({super.key, required this.post});

  @override
  State<CommunityPostImage> createState() => _CommunityPostImageState();
}

class _CommunityPostImageState extends State<CommunityPostImage> {
  Future<String?>? _imageFuture;
  ApiFeedRepository? _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repository = context.watch<AppState>().repository;
    final api = repository is ApiFeedRepository ? repository : null;

    if (!identical(api, _repository)) {
      _repository = api;
      _imageFuture = api?.getPostImageUrl(widget.post.id);
    }
  }

  @override
  void didUpdateWidget(covariant CommunityPostImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Repository reloads create new post objects.
    if (!identical(oldWidget.post, widget.post)) {
      _imageFuture = _repository?.getPostImageUrl(widget.post.id);
    }
  }

  void _retry() {
    setState(() {
      _imageFuture = _repository?.getPostImageUrl(widget.post.id);
    });
  }

  Widget _errorMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.broken_image_outlined),
          const SizedBox(width: 8),
          const Expanded(child: Text('Could not load the post image.')),
          TextButton(onPressed: _retry, child: const Text('Retry')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_imageFuture == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<String?>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }

        if (snapshot.hasError) {
          return _errorMessage();
        }

        final url = snapshot.data;

        if (url == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: Image.network(
                  url,
                  key: ValueKey(url),
                  fit: BoxFit.contain,
                  semanticLabel: 'Image attached to ${widget.post.title}',
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;

                    final total = progress.expectedTotalBytes;

                    return SizedBox(
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: total != null && total > 0
                              ? progress.cumulativeBytesLoaded / total
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _errorMessage();
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
