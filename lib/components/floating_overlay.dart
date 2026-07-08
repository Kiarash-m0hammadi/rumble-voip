import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rumble/services/mumble_service.dart';
import 'package:rumble/components/ptt_button.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FloatingOverlay extends StatefulWidget {
  final VoidCallback onMaximize;
  final bool isExpandedInitial;

  const FloatingOverlay({
    super.key,
    required this.onMaximize,
    this.isExpandedInitial = true,
  });

  @override
  State<FloatingOverlay> createState() => _FloatingOverlayState();
}

class _FloatingOverlayState extends State<FloatingOverlay> {
  Offset _position = const Offset(20, 100);
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isExpandedInitial;
  }

  @override
  Widget build(BuildContext context) {
    final mumbleService = context.watch<MumbleService>();
    final theme = ShadTheme.of(context);
    final size = MediaQuery.of(context).size;

    final talkingUsers = mumbleService.users
        .where((u) => mumbleService.talkingUsers[u.session] ?? false)
        .toList();

    return Positioned(
      left: _position.dx.clamp(0.0, size.width - (_isExpanded ? 240 : 60)),
      top: _position.dy.clamp(0.0, size.height - (_isExpanded ? 150 : 60)),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        child: _isExpanded
            ? _buildExpanded(context, mumbleService, talkingUsers, theme)
            : _buildShrunk(context, theme),
      ),
    );
  }

  Widget _buildShrunk(BuildContext context, ShadThemeData theme) {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = true),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(LucideIcons.mic, color: Colors.black, size: 28),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, MumbleService service, List<dynamic> talkingUsers, ShadThemeData theme) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.background.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.colorScheme.border.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(LucideIcons.gripVertical, size: 16, color: theme.colorScheme.mutedForeground),
                    const Text(
                      'RUMBLE',
                      style: TextStyle(
                        fontWeight: FontWeight.black,
                        fontSize: 10,
                        letterSpacing: 1.2
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onMaximize,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(LucideIcons.maximize2, size: 18, color: theme.colorScheme.primary)
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = false),
                  child: PushToTalkButton(
                    service: service,
                    compact: true,
                    width: double.infinity,
                    height: 56,
                  ),
                ),
                if (talkingUsers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: talkingUsers.map((u) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF64FFDA), // kBrandGreen
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0xFF64FFDA),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  u.name,
                                  style: theme.textTheme.small.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
