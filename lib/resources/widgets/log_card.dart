import '/app/models/engineering_log.dart';
import '/resources/widgets/github_label_picker.dart';
import '/resources/widgets/severity_chip.dart';
import '/resources/widgets/time_meta_text.dart';
import 'package:flutter/material.dart';

class LogCard extends StatelessWidget {
  final EngineeringLog log;
  final VoidCallback? onSync;
  final VoidCallback? onTap;
  final VoidCallback? onCancelDelete;
  final bool confirmDelete;
  final bool pendingSync;

  const LogCard({
    super.key,
    required this.log,
    this.onSync,
    this.onTap,
    this.onCancelDelete,
    this.confirmDelete = false,
    this.pendingSync = false,
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
          padding: const EdgeInsets.all(16),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TypeBadge(type: log.type),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                log.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (!log.isSynced && onSync != null)
              IconButton(
                tooltip: "Sync GitHub",
                onPressed: onSync,
                icon: const Icon(Icons.sync, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TimeMetaText(
          syncAt: log.isSynced ? log.updatedAt : null,
          neverLabel: "Not synced",
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SeverityChip(severity: log.severity),
            _StatusBadge(status: log.syncStatus),
            if (log.githubIssueNumber != null)
              _TextBadge(label: "GitHub #${log.githubIssueNumber}"),
            if (pendingSync)
              const _PendingSyncBadge(),
          ],
        ),
        if (log.labels.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: log.labels
                .map((label) => GithubLabelChip(label: label))
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _confirmContent(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Center(
            child: Text(
              log.githubIssueNumber == null
                  ? "Tap this card again to remove the issue."
                  : "Tap this card again to close GitHub #${log.githubIssueNumber} and remove it.",
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
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final EngineeringLogType type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A28),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.value,
        style: const TextStyle(
          color: Color(0xFFEDECE9),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SyncStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final synced = status != SyncStatus.local;
    final closed = status == SyncStatus.closed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: closed
            ? const Color(0xFF2A2A28)
            : synced
            ? const Color(0xFF173526)
            : const Color(0xFF3B3321),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: closed
              ? const Color(0xFF4A4A46)
              : synced
              ? const Color(0xFF275E42)
              : const Color(0xFF6B5722),
        ),
      ),
      child: Text(
        status.value,
        style: TextStyle(
          color: closed
              ? const Color(0xFFB8B5B0)
              : synced
              ? const Color(0xFF8FE0B2)
              : const Color(0xFFE1C16E),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _TextBadge extends StatelessWidget {
  final String label;

  const _TextBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30302E)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFB8B5B0),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _PendingSyncBadge extends StatelessWidget {
  const _PendingSyncBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF3B3321),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF6B5722)),
      ),
      child: const Text(
        "Pending sync",
        style: TextStyle(
          color: Color(0xFFE1C16E),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
