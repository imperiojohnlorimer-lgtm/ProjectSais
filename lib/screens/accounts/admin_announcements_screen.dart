import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  State<AdminAnnouncementsScreen> createState() => _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  String filterStatus = 'All'; // 'All', 'Open', 'Closed', 'Pending'
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    var anns = state.announcements;
    
    // Apply filter
    if (filterStatus == 'Open') {
      anns = anns.where((a) => a.isOpen).toList();
    } else if (filterStatus == 'Closed') {
      anns = anns.where((a) => !a.isOpen).toList();
    } else if (filterStatus == 'Pending') {
      anns = anns.where((a) => a.isPending).toList();
    } else if (filterStatus == 'Hiring Calls') {
      // Filter by notice category or type
      anns = anns.where((a) => a.acceptsApplications).toList();
    } else if (filterStatus == 'Office Memos') {
      // Filter by memo type
      anns = anns.where((a) => !a.acceptsApplications).toList();
    }
    
    // Apply search
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      anns = anns.where((a) => 
        a.title.toLowerCase().contains(query) ||
        a.body.toLowerCase().contains(query) ||
        a.requirements.any((r) => r.toLowerCase().contains(query))
      ).toList();
    }
    
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────
        // FIX: title + "Post Announcement" button used to sit in one Row
        // with a Spacer and a fixed 28px padding — on a narrow phone the
        // button had nowhere to go and got cut off (the hazard-stripe
        // overflow). Below the mobile breakpoint they stack instead.
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppTheme.maroon,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Announcements',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.emerald50,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Mention Support Active',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.emerald500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Create and manage hiring announcements, call for duties, and memos.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _showPostAnnouncementDialog(context, state),
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text(
                          'Post Announcement',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: AppTheme.maroon,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Announcements',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slate900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.emerald50,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Mention Support Active',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.emerald500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Create and manage hiring announcements, call for duties, and memos.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _showPostAnnouncementDialog(context, state),
                      icon: const Icon(Icons.add_rounded, size: 15),
                      label: const Text(
                        'Post Announcement',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => filterStatus = 'All'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: filterStatus == 'All' ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: filterStatus == 'All'
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                    ),
                    child: Text(
                      'All Notices (${state.announcements.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: filterStatus == 'All'
                            ? Colors.white
                            : AppTheme.slate600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => filterStatus = 'Hiring Calls'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: filterStatus == 'Hiring Calls' ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: filterStatus == 'Hiring Calls'
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                    ),
                    child: Text(
                      'Hiring Calls',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: filterStatus == 'Hiring Calls'
                            ? Colors.white
                            : AppTheme.slate600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => filterStatus = 'Office Memos'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: filterStatus == 'Office Memos' ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: filterStatus == 'Office Memos'
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                    ),
                    child: Text(
                      'Office Memos',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: filterStatus == 'Office Memos'
                            ? Colors.white
                            : AppTheme.slate600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => filterStatus = 'Open'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: filterStatus == 'Open' ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: filterStatus == 'Open'
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                    ),
                    child: Text(
                      'Active Open',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: filterStatus == 'Open'
                            ? Colors.white
                            : AppTheme.slate600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Content ─────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (anns.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: AppTheme.slate100,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.campaign_outlined,
                              size: 36,
                              color: AppTheme.slate300,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No announcements posted yet',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate400,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Use "Post Announcement" to notify students of hiring opportunities.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.slate300,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...anns.map(
                    (a) => _AdminAnnouncementCard(
                      ann: a,
                      state: state,
                      context: context,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMentionTab(String label, [bool isSelected = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.maroon : AppTheme.slate50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.maroon : AppTheme.slate200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : AppTheme.slate600,
          ),
        ),
      ),
    );
  }

  void _showPostAnnouncementDialog(BuildContext context, AppState state) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final deadlineCtrl = TextEditingController(
      text: '${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().year}',
    );
    final slotsCtrl = TextEditingController(text: '3');
    final reqs = <String>['doc', 'docpdf'];
    var acceptsApplications = true;
    var selectedOfficeId = state.offices.isNotEmpty ? state.offices.first.id : '';

    String mentionQuery = '';
    String selectedMentionTab = 'All';
    List<String> suggestions = const [];
    bool isShowingMentions = false;

    String extractMentionQuery(String value, int cursor) {
      final beforeCursor = value.substring(0, cursor.clamp(0, value.length));
      final lastAt = beforeCursor.lastIndexOf('@');
      if (lastAt == -1) return '';
      final fragment = beforeCursor.substring(lastAt + 1);
      if (fragment.contains(' ') || fragment.contains('\n')) return '';
      return fragment;
    }

    void applyMention(String mention) {
      final text = bodyCtrl.text;
      final cursor = bodyCtrl.selection.baseOffset;
      final beforeCursor = text.substring(0, cursor.clamp(0, text.length));
      final lastAt = beforeCursor.lastIndexOf('@');
      if (lastAt == -1) return;
      final prefix = beforeCursor.substring(0, lastAt);
      final suffix = text.substring(cursor.clamp(0, text.length));
      final replacement = '$mention ';
      final nextText = '$prefix$replacement$suffix';
      bodyCtrl.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: prefix.length + replacement.length),
      );
    }

    final mentionableNames = <String>{
      for (final user in state.users)
        if (user.role == 'Student' || user.role == 'Student Assistant' || user.role == 'Supervisor') '@${user.name}',
    }.toList()
      ..sort();
    
    final studentMentions = <String>{
      for (final user in state.users)
        if (user.role == 'Student') '@${user.name}',
    }.toList()
      ..sort();
    
    final assistantMentions = <String>{
      for (final user in state.users)
        if (user.role == 'Student Assistant') '@${user.name}',
    }.toList()
      ..sort();
    
    final supervisorMentions = <String>{
      for (final user in state.users)
        if (user.role == 'Supervisor') '@${user.name}',
    }.toList()
      ..sort();

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          mentionQuery = extractMentionQuery(
            bodyCtrl.text,
            bodyCtrl.selection.baseOffset,
          );
          isShowingMentions = bodyCtrl.text.contains('@');
          
          List<String> tabFilteredMentions = mentionableNames;
          if (selectedMentionTab == 'Students') {
            tabFilteredMentions = studentMentions;
          } else if (selectedMentionTab == 'Student Assistants') {
            tabFilteredMentions = assistantMentions;
          } else if (selectedMentionTab == 'Supervisors') {
            tabFilteredMentions = supervisorMentions;
          }
          
          suggestions = isShowingMentions
              ? tabFilteredMentions
                    .where((item) => item.toLowerCase().contains(
                      mentionQuery.toLowerCase(),
                    ))
                    .take(6)
                    .toList()
              : const [];

          final mentionedPeople = RegExp(r'@([A-Za-z0-9 _-]+)')
              .allMatches(bodyCtrl.text)
              .map((m) => m.group(1)!.trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList();

          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            backgroundColor: Colors.transparent,
            child: Container(
              width: 560,
              constraints: const BoxConstraints(maxHeight: 760),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.maroon, AppTheme.maroonDark],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Post Announcement',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Create a new hiring announcement',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.slate50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.slate200),
                            ),
                            child: TextField(
                              controller: titleCtrl,
                              decoration: InputDecoration(
                                labelText: 'Position Title',
                                labelStyle: const TextStyle(
                                  color: AppTheme.slate600,
                                  fontWeight: FontWeight.w700,
                                ),
                                prefixIcon: const Icon(
                                  Icons.work_outline_rounded,
                                  color: AppTheme.maroon,
                                  size: 17,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.slate50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.slate200),
                            ),
                            child: TextField(
                              controller: bodyCtrl,
                              maxLines: 5,
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Description & Mention Details',
                                labelStyle: const TextStyle(
                                  color: AppTheme.slate600,
                                  fontWeight: FontWeight.w700,
                                ),
                                prefixIcon: const Icon(
                                  Icons.description_outlined,
                                  color: AppTheme.maroon,
                                  size: 17,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          if (suggestions.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.slate200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        GestureDetector(
                                          onTap: () => setDialogState(() => selectedMentionTab = 'All'),
                                          child: _buildMentionTab('All (${mentionableNames.length})', selectedMentionTab == 'All'),
                                        ),
                                        const SizedBox(width: 6),
                                        GestureDetector(
                                          onTap: () => setDialogState(() => selectedMentionTab = 'Students'),
                                          child: _buildMentionTab('Students (${studentMentions.length})', selectedMentionTab == 'Students'),
                                        ),
                                        const SizedBox(width: 6),
                                        GestureDetector(
                                          onTap: () => setDialogState(() => selectedMentionTab = 'Student Assistants'),
                                          child: _buildMentionTab('Student Assistants (${assistantMentions.length})', selectedMentionTab == 'Student Assistants'),
                                        ),
                                        const SizedBox(width: 6),
                                        GestureDetector(
                                          onTap: () => setDialogState(() => selectedMentionTab = 'Supervisors'),
                                          child: _buildMentionTab('Supervisors (${supervisorMentions.length})', selectedMentionTab == 'Supervisors'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Divider(color: AppTheme.slate200, height: 1),
                                  Container(
                                    constraints: const BoxConstraints(maxHeight: 200),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: suggestions.length,
                                      separatorBuilder: (context, index) => Divider(
                                        color: AppTheme.slate100,
                                        height: 1,
                                      ),
                                      itemBuilder: (context, index) {
                                        final mention = suggestions[index];
                                        return InkWell(
                                          onTap: () {
                                            applyMention(mention);
                                            setDialogState(() {});
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.maroon,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      mention[1].toUpperCase(),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        mention,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: AppTheme.slate800,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        'Student',
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          color: AppTheme.slate500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () {
                                                    applyMention(mention);
                                                    setDialogState(() {});
                                                  },
                                                  child: const Text(
                                                    'Enter',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                      color: AppTheme.maroon,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (mentionedPeople.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: mentionedPeople
                                  .map(
                                    (person) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.maroon.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: AppTheme.maroon.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        '@$person',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.maroon,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.slate50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.slate200),
                            ),
                            child: DropdownButton<String>(
                              value: selectedOfficeId.isEmpty ? null : selectedOfficeId,
                              hint: const Padding(
                                padding: EdgeInsets.only(left: 14),
                                child: Text(
                                  'Select Office',
                                  style: TextStyle(
                                    color: AppTheme.slate600,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              isExpanded: true,
                              underline: const SizedBox(),
                              onChanged: (String? value) {
                                setDialogState(() => selectedOfficeId = value ?? '');
                              },
                              items: state.offices.map((office) {
                                return DropdownMenuItem(
                                  value: office.id,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 14),
                                    child: Text(
                                      office.name,
                                      style: const TextStyle(
                                        color: AppTheme.slate800,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.slate50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.slate200),
                                  ),
                                  child: TextField(
                                    controller: deadlineCtrl,
                                    readOnly: true,
                                    onTap: () async {
                                      final now = DateTime.now();
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: now,
                                        firstDate: DateTime(now.year - 1),
                                        lastDate: DateTime(now.year + 5),
                                      );
                                      if (picked == null) return;
                                      final months = const [
                                        'Jan',
                                        'Feb',
                                        'Mar',
                                        'Apr',
                                        'May',
                                        'Jun',
                                        'Jul',
                                        'Aug',
                                        'Sep',
                                        'Oct',
                                        'Nov',
                                        'Dec',
                                      ];
                                      deadlineCtrl.text =
                                          '${months[picked.month - 1]} ${picked.day}, ${picked.year}';
                                    },
                                    decoration: InputDecoration(
                                      labelText: 'Deadline',
                                      labelStyle: const TextStyle(
                                        color: AppTheme.slate600,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.event_rounded,
                                        color: AppTheme.maroon,
                                        size: 17,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.slate50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.slate200),
                                  ),
                                  child: TextField(
                                    controller: slotsCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Available Slots',
                                      labelStyle: const TextStyle(
                                        color: AppTheme.slate600,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.people_outline_rounded,
                                        color: AppTheme.maroon,
                                        size: 17,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.slate50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.slate200),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: const [
                                      Text(
                                        'Accept applications',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.slate800,
                                        ),
                                      ),
                                      Text(
                                        'Turn off for a normal announcement',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.slate500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: acceptsApplications,
                                  activeThumbColor: AppTheme.maroon,
                                  onChanged: (value) =>
                                      setDialogState(() => acceptsApplications = value),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'REQUIREMENTS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate500,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.slate50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.slate200),
                            ),
                            child: Column(
                              children: [
                                if (reqs.isNotEmpty)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: reqs.asMap().entries.map((entry) {
                                      final item = entry.value;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.maroon.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: AppTheme.maroon.withValues(
                                              alpha: 0.2,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              item,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.maroon,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            GestureDetector(
                                              onTap: () => setDialogState(() {
                                                reqs.removeAt(entry.key);
                                              }),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                size: 12,
                                                color: AppTheme.maroon,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                const SizedBox(height: 10),
                                TextField(
                                  onSubmitted: (value) {
                                    final clean = value.trim();
                                    if (clean.isEmpty || reqs.contains(clean)) {
                                      return;
                                    }
                                    setDialogState(() => reqs.add(clean));
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Add requirement (press Enter)',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: AppTheme.slate200,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: AppTheme.slate200,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: AppTheme.maroon,
                                        width: 1.5,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final title = titleCtrl.text.trim();
                          final body = bodyCtrl.text.trim();
                          final slotsText = slotsCtrl.text.trim();
                          final errors = <String>[];
                          if (title.isEmpty) errors.add('Title is required.');
                          if (title.length < 3) {
                            errors.add('Title must be at least 3 characters.');
                          }
                          if (title.length > 100) {
                            errors.add('Title must be at most 100 characters.');
                          }
                          if (body.isEmpty) errors.add('Description is required.');
                          if (body.length < 10) {
                            errors.add('Description must be at least 10 characters.');
                          }
                          if (body.length > 2000) {
                            errors.add('Description is too long.');
                          }
                          if (slotsText.isNotEmpty) {
                            final slots = int.tryParse(slotsText);
                            if (slots == null || slots <= 0) {
                              errors.add('Available slots must be a positive number.');
                            }
                          }
                          if (errors.isNotEmpty) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errors.join('\n')),
                                backgroundColor: AppTheme.red500,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                            return;
                          }

                          final today =
                              '${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().year}';
                          final ok = await state.postAnnouncement(
                            Announcement(
                              id: 'ann_${DateTime.now().millisecondsSinceEpoch}',
                              title: title,
                              body: body,
                              postedBy: state.currentUser?.name ?? 'Admin',
                              postedAt: today,
                              deadline: deadlineCtrl.text.trim().isEmpty
                                  ? null
                                  : deadlineCtrl.text.trim(),
                              slots: slotsText.isEmpty ? null : slotsText,
                              requirements: reqs,
                              acceptsApplications: acceptsApplications,
                            ),
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          if (ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Announcement posted! Students have been notified.',
                                ),
                                backgroundColor: AppTheme.emerald500,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Failed to post announcement. Please try again.',
                                ),
                                backgroundColor: AppTheme.red500,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text(
                          'Post Announcement',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AdminAnnouncementCard extends StatelessWidget {
  final Announcement ann;
  final AppState state;
  final BuildContext context;
  const _AdminAnnouncementCard({
    required this.ann,
    required this.state,
    required this.context,
  });

  @override
  Widget build(BuildContext ctx) {
    final appCount = state.applications
        .where((a) => a.announcementId == ann.id)
        .length;
    final isMobile = MediaQuery.of(ctx).size.width < 700;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slate100, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppTheme.slate900.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top: icon, title, status ─────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.maroon, AppTheme.maroonDark],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.maroon.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ann.title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slate900,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_rounded,
                            size: 12,
                            color: AppTheme.slate300,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${ann.postedBy} · ${ann.postedAt}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.slate400,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: ann.isPending
                        ? AppTheme.amber500.withValues(alpha: 0.12)
                        : ann.isRejected
                        ? AppTheme.red500.withValues(alpha: 0.1)
                        : ann.isOpen
                        ? AppTheme.emerald50
                        : AppTheme.slate100,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: ann.isPending
                              ? AppTheme.amber500
                              : ann.isRejected
                              ? AppTheme.red500
                              : ann.isOpen
                              ? AppTheme.emerald500
                              : AppTheme.slate400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        ann.isPending
                            ? 'Pending Approval'
                            : ann.isRejected
                            ? 'Rejected'
                            : ann.isOpen
                            ? 'Open'
                            : 'Closed',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: ann.isPending
                              ? AppTheme.amber500
                              : ann.isRejected
                              ? AppTheme.red500
                              : ann.isOpen
                              ? AppTheme.emerald500
                              : AppTheme.slate600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Body ──────────────────────────────────────────
          if (ann.officeName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppTheme.maroon.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.apartment_rounded,
                      size: 13,
                      color: AppTheme.maroon,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ann.officeName!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.maroon,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              ann.body,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.slate600,
                height: 1.55,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ann.requirements.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ann.requirements
                    .map(
                      (req) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.maroon.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.maroon.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          req,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.maroon,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (ann.deadline != null)
                  _Chip(
                    Icons.event_rounded,
                    'Due ${ann.deadline!}',
                    AppTheme.amber500,
                  ),
                if (ann.slots != null)
                  _Chip(
                    Icons.people_rounded,
                    '${ann.slots} slots',
                    AppTheme.blue500,
                  ),
                _Chip(
                  Icons.assignment_turned_in_rounded,
                  '$appCount applied',
                  AppTheme.maroon,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppTheme.slate100),
          // ── Actions ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: isMobile
                ? Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.visibility_outlined,
                          label: 'View',
                          color: AppTheme.slate600,
                          onTap: () => _showAnnouncementDetails(ctx, ann),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (ann.isPending) ...[
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.check_rounded,
                            label: 'Approve',
                            color: AppTheme.emerald500,
                            onTap: () =>
                                ctx.read<AppState>().approveAnnouncement(ann.id),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.close_rounded,
                            label: 'Reject',
                            color: AppTheme.red500,
                            onTap: () =>
                                _showRejectDialog(ctx, ann.id),
                          ),
                        ),
                      ] else
                        Expanded(
                          child: ann.isOpen
                              ? _ActionButton(
                                  icon: Icons.lock_outline_rounded,
                                  label: 'Close',
                                  color: AppTheme.slate600,
                                  onTap: () =>
                                      ctx.read<AppState>().closeAnnouncement(ann.id),
                                )
                              : _ActionButton(
                                  icon: Icons.check_rounded,
                                  label: 'Re-open',
                                  color: AppTheme.emerald500,
                                  onTap: () => ctx
                                      .read<AppState>()
                                      .approveAnnouncement(ann.id),
                                ),
                        ),
                      const SizedBox(width: 6),
                      _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        label: '',
                        color: AppTheme.red500,
                        iconOnly: true,
                        onTap: () =>
                            ctx.read<AppState>().deleteAnnouncement(ann.id),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text(
                            'Direct notifications dispatched',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.slate400,
                            ),
                          ),
                        ),
                      ),
                      _ActionButton(
                        icon: Icons.visibility_outlined,
                        label: 'View Details',
                        color: AppTheme.slate600,
                        onTap: () => _showAnnouncementDetails(ctx, ann),
                      ),
                      const SizedBox(width: 8),
                      if (ann.isPending) ...[
                        _ActionButton(
                          icon: Icons.check_rounded,
                          label: 'Approve',
                          color: AppTheme.emerald500,
                          onTap: () =>
                              ctx.read<AppState>().approveAnnouncement(ann.id),
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.close_rounded,
                          label: 'Reject',
                          color: AppTheme.red500,
                          onTap: () => _showRejectDialog(ctx, ann.id),
                        ),
                      ] else
                        ann.isOpen
                            ? _ActionButton(
                                icon: Icons.lock_outline_rounded,
                                label: 'Close',
                                color: AppTheme.slate600,
                                onTap: () =>
                                    ctx.read<AppState>().closeAnnouncement(ann.id),
                              )
                            : _ActionButton(
                                icon: Icons.check_rounded,
                                label: 'Re-open',
                                color: AppTheme.emerald500,
                                onTap: () =>
                                    ctx.read<AppState>().approveAnnouncement(ann.id),
                              ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        color: AppTheme.red500,
                        onTap: () =>
                            ctx.read<AppState>().deleteAnnouncement(ann.id),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context, String announcementId) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Reject Request',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Let the supervisor know why this request is being rejected (optional).',
              style: TextStyle(fontSize: 13, color: AppTheme.slate600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Reason for rejection',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.slate200),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.red500,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              dialogContext.read<AppState>().rejectAnnouncement(
                announcementId,
                reason: reasonCtrl.text.trim().isEmpty
                    ? null
                    : reasonCtrl.text.trim(),
              );
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  void _showAnnouncementDetails(BuildContext context, Announcement ann) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 520,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.maroon, AppTheme.maroonDark],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Announcement Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ann.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: AppTheme.slate400,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Posted by ${ann.postedBy}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          ann.postedAt,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      ann.body,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.slate700,
                        height: 1.7,
                      ),
                    ),
                    if (ann.requirements.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'Requirements',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ann.requirements
                            .map(
                              (req) => _Chip(
                                Icons.check_circle_outline,
                                req,
                                AppTheme.maroon,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (ann.deadline != null)
                          _Chip(
                            Icons.event_rounded,
                            'Due ${ann.deadline!}',
                            AppTheme.amber500,
                          ),
                        if (ann.slots != null)
                          _Chip(
                            Icons.people_rounded,
                            '${ann.slots} slots',
                            AppTheme.blue500,
                          ),
                        _Chip(
                          Icons.info_outline,
                          ann.isPending
                              ? 'Pending approval'
                              : ann.isApproved
                              ? (ann.isOpen ? 'Open' : 'Closed')
                              : 'Rejected',
                          ann.isPending
                              ? AppTheme.amber500
                              : ann.isApproved
                              ? (ann.isOpen
                                    ? AppTheme.emerald500
                                    : AppTheme.slate400)
                              : AppTheme.red500,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool iconOnly;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 10 : 12,
            vertical: 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              if (!iconOnly) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}