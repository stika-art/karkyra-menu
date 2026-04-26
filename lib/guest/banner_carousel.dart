import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

class BannerCarousel extends StatefulWidget {
  final List<Map<String, String>> banners;
  const BannerCarousel({super.key, required this.banners});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isMuted = true;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (widget.banners.length > 1) {
        final nextIndex = (_currentIndex + 1) % widget.banners.length;
        _pageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              _startAutoPlay();
            },
            itemCount: widget.banners.length,
            itemBuilder: (context, index) {
              final banner = widget.banners[index];
              return BannerItem(
                banner: banner,
                isActive: index == _currentIndex,
                isMuted: _isMuted,
              );
            },
          ),
          // Gradient Overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.3),
                      Colors.transparent,
                      Colors.black.withOpacity(0.2),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Progress Dots
          if (widget.banners.length > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.banners.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentIndex == index ? 24 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _currentIndex == index 
                          ? const Color(0xFFD4A043) 
                          : Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          // Mute Toggle
          if (widget.banners[_currentIndex]['type'] == 'video')
            Positioned(
              bottom: 20,
              right: 20,
              child: GestureDetector(
                onTap: () => setState(() => _isMuted = !_isMuted),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Icon(
                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BannerItem extends StatefulWidget {
  final Map<String, String> banner;
  final bool isActive;
  final bool isMuted;

  const BannerItem({
    super.key,
    required this.banner,
    required this.isActive,
    required this.isMuted,
  });

  @override
  State<BannerItem> createState() => _BannerItemState();
}

class _BannerItemState extends State<BannerItem> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.banner['type'] == 'video') {
      _initController();
    }
  }

  Future<void> _initController() async {
    final url = widget.banner['url'] ?? '';
    if (url.isEmpty) return;

    _controller = url.startsWith('assets/')
        ? VideoPlayerController.asset(url)
        : VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _controller!.setLooping(true);
          _controller!.setVolume(widget.isMuted ? 0 : 1.0);
          if (widget.isActive) _controller!.play();
        });
      }
    } catch (e) {
      debugPrint('Banner Video Error: $e');
    }
  }

  @override
  void didUpdateWidget(BannerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null) return;

    if (widget.isActive) {
      _controller!.play();
    } else {
      _controller!.pause();
    }
    _controller!.setVolume(widget.isMuted ? 0 : 1.0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.banner['type'] == 'video';

    return VisibilityDetector(
      key: Key('banner_${widget.banner['url']}'),
      onVisibilityChanged: (info) {
        if (!mounted || _controller == null) return;
        if (info.visibleFraction < 0.5) {
          _controller!.pause();
        } else if (widget.isActive) {
          _controller!.play();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Placeholder / Image
          _buildPlaceholder(),
          // Video
          if (isVideo && _controller != null)
            AnimatedOpacity(
              opacity: _isInitialized ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 800),
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    final previewUrl = widget.banner['preview_url'];
    final url = widget.banner['url'] ?? '';
    final isVideo = widget.banner['type'] == 'video';
    final displayUrl = (previewUrl != null && previewUrl.isNotEmpty) 
        ? previewUrl 
        : (!isVideo ? url : null);

    if (displayUrl == null || displayUrl.isEmpty) {
      return Container(color: Colors.black);
    }

    return Image.network(
      displayUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: Colors.black),
    );
  }
}
