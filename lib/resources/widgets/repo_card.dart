import '/app/models/repository.dart';
import '/resources/widgets/time_meta_text.dart';
import 'package:flutter/material.dart';

class RepoCard extends StatelessWidget {
  final Repository repository;
  final int logs;
  final int draft;
  final int synced;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onCancelDelete;
  final bool confirmDelete;

  const RepoCard({
    super.key,
    required this.repository,
    required this.logs,
    required this.draft,
    required this.synced,
    this.onTap,
    this.onDelete,
    this.onCancelDelete,
    this.confirmDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: confirmDelete
              ? const Color(0xFF6D2A2A)
              : const Color(0xFF30302E),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: confirmDelete
              ? Stack(
                  children: [
                    IgnorePointer(
                      child: Opacity(opacity: 0, child: _content(context)),
                    ),
                    Positioned.fill(child: _confirmContent(context)),
                  ],
                )
              : _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                repository.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: "Remove repository",
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
              )
            else
              const Icon(Icons.chevron_right, size: 20),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          repository.owner,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFFB8B5B0),
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _Metric(label: "Logs", value: logs),
            _Metric(label: "Open", value: draft),
            _Metric(label: "Finished", value: synced),
          ],
        ),
        const SizedBox(height: 12),
        TimeMetaText(syncAt: repository.lastSync),
      ],
    );
  }

  Widget _confirmContent(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Center(
            child: Text(
              "Tap this card again to remove the repository.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFFFFB4B4),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
        if (onCancelDelete != null)
          IconButton(
            tooltip: "Cancel delete",
            onPressed: onCancelDelete,
            icon: const Icon(Icons.close, size: 18),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toString(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFFB8B5B0),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
