import 'dart:convert' show base64Encode;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import 'dart:html' if (dart.library.html) 'dart:html' as html;

const _roles = ['Admin', 'Head', 'Supervisor', 'Student Assistant', 'Student'];

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _search = '';
  String _filterRole = 'All';
  String _filterDept = 'All Departments';
  String _filterCampus = 'All Campuses';
  bool _showArchived = false;
  final List<String> _campusFilters = [
    'All Campuses',
    'Boac Campus',
    'Mogpog Campus',
    'Sta. Cruz Campus',
    'Torrijos Campus',
    'Gasan Campus',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 1, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final adminCount = state.users
        .where((u) => u.role == 'Admin' && u.status != 'Archived')
        .length;
    final headCount = state.users
        .where((u) => u.role == 'Head' && u.status != 'Archived')
        .length;
    final supervisorCount = state.users
        .where((u) => u.role == 'Supervisor' && u.status != 'Archived')
        .length;
    final studentAssistantCount = state.users
        .where((u) => u.role == 'Student Assistant' && u.status != 'Archived')
        .length;
    final studentCount = state.users
        .where((u) => u.role == 'Student' && u.status != 'Archived')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ΓöÇΓöÇ Header ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
        Padding(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.of(context).size.width < 700 ? 16.0 : 28.0,
            24,
            MediaQuery.of(context).size.width < 700 ? 16.0 : 28.0,
            0,
          ),
          child: Row(
            children: [
              Column(
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
                        'Accounts',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slate900,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 14, top: 3),
                    child: Text(
                      'Manage user accounts and roles',
                      style: TextStyle(fontSize: 13, color: AppTheme.slate400),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showUserDialog(context, state),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: const Text(
                  'Add Account',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ΓöÇΓöÇ Content ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
        Expanded(
          child: _buildAccountsTab(
            context,
            state,
            adminCount,
            headCount,
            supervisorCount,
            studentCount,
            studentAssistantCount,
          ),
        ),
      ],
    );
  }

  // ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
  // ACCOUNTS TAB (original content)
  // ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
  Widget _buildAccountsTab(
    BuildContext context,
    AppState state,
    int adminCount,
    int headCount,
    int supervisorCount,
    int studentCount,
    int studentAssistantCount,
  ) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;
    final users = state.users.where((u) {
      final q = _search.toLowerCase();
      final matchSearch =
          q.isEmpty ||
          u.name.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
      final matchRole = _filterRole == 'All' || u.role == _filterRole;
      final matchDept =
          _filterDept == 'All Departments' ||
          (u.department ?? '') == _filterDept;
      final matchCampus =
          _filterCampus == 'All Campuses' || (u.campus ?? '') == _filterCampus;
      final matchArchived = _showArchived
          ? u.status == 'Archived'
          : u.status != 'Archived';
      return matchSearch &&
          matchRole &&
          matchDept &&
          matchCampus &&
          matchArchived;
    }).toList();

    return SingleChildScrollView(
      primary: false,
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ΓöÇΓöÇ Stat cards ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
          const SizedBox(height: 4),
          isMobile
              // FIX: GridView.count with a fixed childAspectRatio forced each
              // card into a height too short for its content at narrow
              // widths (that was the "BOTTOM OVERFLOWED BY 12 PIXELS"
              // warning). Two plain Rows let each card's height follow its
              // own content instead of a hard-coded ratio.
              ? Column(
                  children: [
                    Row(
                      children: [
                        _StatCard(
                          label: 'ADMINS',
                          count: adminCount,
                          color: AppTheme.red500,
                          icon: Icons.admin_panel_settings_outlined,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'HEADS',
                          count: headCount,
                          color: AppTheme.violet500,
                          icon: Icons.workspace_premium_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatCard(
                          label: 'SUPERVISORS',
                          count: supervisorCount,
                          color: AppTheme.amber500,
                          icon: Icons.supervisor_account_outlined,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'STUDENTS',
                          count: studentCount,
                          color: AppTheme.emerald500,
                          icon: Icons.school_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatCard(
                          label: 'ASSISTANTS',
                          count: studentAssistantCount,
                          color: AppTheme.blue500,
                          icon: Icons.handyman_outlined,
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    _StatCard(
                      label: 'ADMINS',
                      count: adminCount,
                      color: AppTheme.red500,
                      icon: Icons.admin_panel_settings_outlined,
                    ),
                    const SizedBox(width: 14),
                    _StatCard(
                      label: 'HEADS',
                      count: headCount,
                      color: AppTheme.violet500,
                      icon: Icons.workspace_premium_outlined,
                    ),
                    const SizedBox(width: 14),
                    _StatCard(
                      label: 'SUPERVISORS',
                      count: supervisorCount,
                      color: AppTheme.amber500,
                      icon: Icons.supervisor_account_outlined,
                    ),
                    const SizedBox(width: 14),
                    _StatCard(
                      label: 'STUDENTS',
                      count: studentCount,
                      color: AppTheme.emerald500,
                      icon: Icons.school_outlined,
                    ),
                    const SizedBox(width: 14),
                    _StatCard(
                      label: 'ASSISTANTS',
                      count: studentAssistantCount,
                      color: AppTheme.blue500,
                      icon: Icons.handyman_outlined,
                    ),
                  ],
                ),
          const SizedBox(height: 20),

          // ΓöÇΓöÇ Filters row ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
          if (isMobile) ...[
            TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search accounts...',
                hintStyle: const TextStyle(
                  color: AppTheme.slate400,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppTheme.slate400,
                  size: 18,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.slate200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.slate200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.maroon,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterDept,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.slate700,
                    fontWeight: FontWeight.w500,
                  ),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.slate400,
                    size: 18,
                  ),
                  items: ['All Departments', ...state.departments]
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(d, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _filterDept = v!),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterCampus,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.slate700,
                    fontWeight: FontWeight.w500,
                  ),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.slate400,
                    size: 18,
                  ),
                  items: _campusFilters
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _filterCampus = v!),
                ),
              ),
            ),
          ] else
            Row(
              children: [
                // Search
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search accounts...',
                      hintStyle: const TextStyle(
                        color: AppTheme.slate400,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppTheme.slate400,
                        size: 18,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.slate200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.slate200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.maroon,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Department dropdown
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterDept,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.slate700,
                        fontWeight: FontWeight.w500,
                      ),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.slate400,
                        size: 18,
                      ),
                      items: ['All Departments', ...state.departments]
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text(d, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _filterDept = v!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Campus dropdown
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterCampus,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.slate700,
                        fontWeight: FontWeight.w500,
                      ),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.slate400,
                        size: 18,
                      ),
                      items: _campusFilters
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(c, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _filterCampus = v!),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),

          // Role filter chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!isMobile)
                const Text(
                  'FILTER BY ROLE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate400,
                    letterSpacing: 0.8,
                  ),
                ),
              ...(['All', ..._roles].map(
                (r) => GestureDetector(
                  onTap: () => setState(() => _filterRole = r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _filterRole == r ? AppTheme.maroon : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _filterRole == r
                            ? AppTheme.maroon
                            : AppTheme.slate200,
                      ),
                      boxShadow: _filterRole == r
                          ? [
                              BoxShadow(
                                color: AppTheme.maroon.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      r,
                      style: TextStyle(
                        color: _filterRole == r
                            ? Colors.white
                            : AppTheme.slate600,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              )),
            ],
          ),
          const SizedBox(height: 12),
          // Archived toggle
          GestureDetector(
            onTap: () => setState(() => _showArchived = !_showArchived),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _showArchived ? AppTheme.amber50 : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _showArchived
                      ? AppTheme.amber500.withValues(alpha: 0.4)
                      : AppTheme.slate200,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.archive_outlined,
                    size: 15,
                    color: _showArchived
                        ? AppTheme.amber500
                        : AppTheme.slate400,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showArchived
                        ? 'Showing archived accounts'
                        : 'Show archived accounts',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _showArchived
                          ? AppTheme.amber500
                          : AppTheme.slate500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.maroon.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              children: [
                // Top accent
                Container(
                  height: 5,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.maroon, AppTheme.maroonDark],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                ),
                // Table header ΓÇö the 4-column layout only makes sense on
                // wider screens; on mobile the rows below switch to a
                // stacked card layout so a matching header isn't needed.
                if (!isMobile)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      border: Border(
                        bottom: BorderSide(color: AppTheme.slate100),
                      ),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 44),
                        SizedBox(width: 12),
                        Expanded(flex: 3, child: _ColHeader('USER')),
                        Expanded(flex: 2, child: _ColHeader('ROLE')),
                        Expanded(flex: 3, child: _ColHeader('DEPARTMENT')),
                        Expanded(flex: 2, child: _ColHeader('CAMPUS')),
                        SizedBox(
                          width: 144,
                          child: _ColHeader('ACTIONS', center: true),
                        ),
                      ],
                    ),
                  ),
                // Rows
                if (users.isEmpty)
                  _emptyState()
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: users.length,
                    separatorBuilder: (_, __) =>
                        Container(height: 1, color: AppTheme.slate100),
                    itemBuilder: (_, i) => _AccountRow(
                      user: users[i],
                      state: state,
                      isMobile: isMobile,
                      onView: () => _showUserProfile(context, state, users[i]),
                      onEdit: () =>
                          _showUserDialog(context, state, user: users[i]),
                      onDelete: () async {
                        final ok = await showConfirmDialog(
                          context,
                          title: 'Delete Account Permanently',
                          message:
                              'Delete ${users[i].name} from the system? This removes the Firestore profile and cannot be undone.',
                          confirmLabel: 'Delete',
                          confirmColor: AppTheme.red500,
                        );
                        if (!ok) return;
                        await state.deleteManagedUser(users[i].id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Account profile deleted from the system.',
                            ),
                            backgroundColor: AppTheme.emerald500,
                            behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                        );
                      },
                      onArchiveToggle: () async {
                        if (users[i].id == state.currentUser?.id) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "You can't archive your own account.",
                              ),
                              backgroundColor: AppTheme.red500,
                              behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                          );
                          return;
                        }
                        if (users[i].status == 'Archived') {
                          await state.restoreUser(users[i].id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Account "${users[i].name}" restored',
                              ),
                              backgroundColor: AppTheme.emerald500,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                          );
                          return;
                        }
                        final ok = await showConfirmDialog(
                          context,
                          title: 'Archive Account',
                          message:
                              "Archive ${users[i].name}'s account? They'll be unable to log in, and can be restored later.",
                          confirmLabel: 'Archive',
                          confirmColor: AppTheme.amber500,
                        );
                        if (ok) {
                          await state.archiveUser(users[i].id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Account "${users[i].name}" archived',
                              ),
                              backgroundColor: AppTheme.amber500,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                          );
                        }
                      },
                    ),
                  ),
                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.slate50,
                    border: Border(top: BorderSide(color: AppTheme.slate100)),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                  child: Text(
                    '${users.length} account${users.length != 1 ? 's' : ''} found',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.slate400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  } // end _buildAccountsTab

  // ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
  // ANNOUNCEMENTS TAB
  // ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
  // ignore: unused_element
  Widget _buildAnnouncementsTab(BuildContext context, AppState state) {
    final anns = state.announcements;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
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
                      style: TextStyle(fontSize: 12, color: AppTheme.slate300),
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
    );
  }

  // ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
  // APPLICATIONS TAB
  // ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
  // ignore: unused_element
  Widget _buildApplicationsTab(BuildContext context, AppState state) {
    final apps = state.applications;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (apps.isEmpty)
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
                        Icons.assignment_outlined,
                        size: 36,
                        color: AppTheme.slate300,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No applications received yet',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slate400,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...apps.map(
              (a) => _AdminApplicationCard(app: a, state: state, ctx: context),
            ),
        ],
      ),
    );
  }

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppTheme.slate50,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.manage_accounts_outlined,
            size: 28,
            color: AppTheme.slate300,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'No accounts found',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.slate400,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Try adjusting your search or filter',
          style: TextStyle(fontSize: 12, color: AppTheme.slate300),
        ),
      ],
    ),
  );

  // ignore: unused_element
  void _showPostAnnouncementDialog(BuildContext context, AppState state) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final deadlineCtrl = TextEditingController();
    final slotsCtrl = TextEditingController();
    final reqCtrl = TextEditingController();
    var acceptsApplications = true;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 680),
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
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.maroon, AppTheme.maroonDark],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.campaign_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Post Hiring Announcement',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Students will see this in their portal',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dialogField(
                        'Announcement Title *',
                        titleCtrl,
                        Icons.title_rounded,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: bodyCtrl,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Description / Details *',
                          prefixIcon: const Icon(
                            Icons.description_outlined,
                            color: AppTheme.maroon,
                            size: 17,
                          ),
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
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _dialogField(
                              'Deadline (e.g. June 5, 2026)',
                              deadlineCtrl,
                              Icons.event_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dialogField(
                              'No. of Slots',
                              slotsCtrl,
                              Icons.people_outline,
                              type: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: reqCtrl,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Requirements (one per line)',
                          hintText:
                              'e.g. Certificate of Registration\nGrade Slip',
                          hintStyle: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate400,
                          ),
                          prefixIcon: const Icon(
                            Icons.checklist_rounded,
                            color: AppTheme.maroon,
                            size: 17,
                          ),
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
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      StatefulBuilder(
                        builder: (context, setState) => SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Accept applications'),
                          subtitle: const Text(
                            'Turn off for a normal announcement',
                          ),
                          value: acceptsApplications,
                          onChanged: (value) =>
                              setState(() => acceptsApplications = value),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (titleCtrl.text.trim().isEmpty ||
                                bodyCtrl.text.trim().isEmpty)
                              return;
                            final now = DateTime.now();
                            const months = [
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
                            final today =
                                '${months[now.month - 1]} ${now.day}, ${now.year}';
                            final reqs = reqCtrl.text.trim().isEmpty
                                ? <String>[]
                                : reqCtrl.text
                                      .trim()
                                      .split('\n')
                                      .map((r) => r.trim())
                                      .where((r) => r.isNotEmpty)
                                      .toList();
                            state.postAnnouncement(
                              Announcement(
                                id: 'ann_${DateTime.now().millisecondsSinceEpoch}',
                                title: titleCtrl.text.trim(),
                                body: bodyCtrl.text.trim(),
                                postedBy: state.currentUser?.name ?? 'Admin',
                                postedAt: today,
                                deadline: deadlineCtrl.text.trim().isEmpty
                                    ? null
                                    : deadlineCtrl.text.trim(),
                                slots: slotsCtrl.text.trim().isEmpty
                                    ? null
                                    : slotsCtrl.text.trim(),
                                requirements: reqs,
                                acceptsApplications: acceptsApplications,
                              ),
                            );
                            Navigator.pop(context);
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
                          },
                          icon: const Icon(Icons.send_rounded, size: 16),
                          label: const Text(
                            'Post Announcement',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogField(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    TextInputType? type,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.maroon, size: 17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.maroon, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Future<void> _showUserDialog(
    BuildContext context,
    AppState state, {
    User? user,
  }) async {
    final isEditing = user != null;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final nameCtrl = TextEditingController(text: user?.name ?? '');
    final emailCtrl = TextEditingController(text: user?.email ?? '');
    final passwordCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: user?.phone ?? '');
    final studentIdCtrl = TextEditingController(text: user?.studentId ?? '');
    final courseProgramCtrl = TextEditingController(text: user?.courseProgram ?? '');
    var yearLevel = user?.yearLevel ?? '1st Year';
    var role = user?.role ?? 'Student';
    final departmentOptions = state.departments.isEmpty
        ? const ['Administration']
        : state.departments;
    final selectedSkills = {...(user?.skills ?? const <String>[])};
    var department = user?.department ?? departmentOptions.first;
    var campus = user?.campus ?? _campusFilters[1];

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 40,
            vertical: isMobile ? 20 : 24,
          ),
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Text(isEditing ? 'Edit Account' : 'Create Account'),
          content: SizedBox(
            width: isMobile ? double.infinity : 430,
            height: isMobile ? MediaQuery.of(context).size.height * 0.62 : null,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogField('Full name *', nameCtrl, Icons.person_outline),
                  const SizedBox(height: 12),
                  _dialogField(
                    'Email *',
                    emailCtrl,
                    Icons.email_outlined,
                    type: TextInputType.emailAddress,
                  ),
                  if (!isEditing) ...[
                    const SizedBox(height: 12),
                    _dialogField(
                      'Temporary password *',
                      passwordCtrl,
                      Icons.lock_outline,
                      type: TextInputType.visiblePassword,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _accountDropdown(
                    'Role',
                    role,
                    _roles,
                    (value) => setDialogState(() => role = value),
                    Icons.badge_outlined,
                  ),
                  const SizedBox(height: 12),
                  _accountDropdown(
                    'Department',
                    department,
                    departmentOptions,
                    (value) => setDialogState(() => department = value),
                    Icons.business_outlined,
                  ),
                  const SizedBox(height: 12),
                  _accountDropdown(
                    'Campus',
                    campus,
                    _campusFilters.skip(1).toList(),
                    (value) => setDialogState(() => campus = value),
                    Icons.location_city_outlined,
                  ),
                  if (state.skills.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Skills',
                        prefixIcon: Icon(Icons.stars_outlined),
                      ),
                      child: Column(
                        children: state.skills
                            .map(
                              (skill) => CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(skill),
                                value: selectedSkills.contains(skill),
                                onChanged: (checked) => setDialogState(() {
                                  if (checked == true) {
                                    selectedSkills.add(skill);
                                  } else {
                                    selectedSkills.remove(skill);
                                  }
                                }),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _dialogField(
                    'Phone (optional)',
                    phoneCtrl,
                    Icons.phone_outlined,
                    type: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    'Student ID (optional)',
                    studentIdCtrl,
                    Icons.badge_outlined,
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    'Course/Program (optional)',
                    courseProgramCtrl,
                    Icons.school_outlined,
                  ),
                  const SizedBox(height: 12),
                  _accountDropdown(
                    'Year level',
                    yearLevel,
                    const ['1st Year', '2nd Year', '3rd Year', '4th Year'],
                    (value) => setDialogState(() => yearLevel = value),
                    Icons.timeline_outlined,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty ||
                    emailCtrl.text.trim().isEmpty ||
                    (!isEditing && passwordCtrl.text.length < 6))
                  return;
                final managedUser =
                    (user ?? User(id: '', name: '', email: '', role: role))
                        .copyWith(
                          name: nameCtrl.text.trim(),
                          role: role,
                          department: department,
                          campus: campus,
                          phone: phoneCtrl.text.trim().isEmpty
                              ? null
                              : phoneCtrl.text.trim(),
                          studentId: studentIdCtrl.text.trim().isEmpty
                              ? null
                              : studentIdCtrl.text.trim(),
                          courseProgram: courseProgramCtrl.text.trim().isEmpty
                              ? null
                              : courseProgramCtrl.text.trim(),
                          yearLevel: yearLevel,
                          skills: selectedSkills.toList(),
                        );
                String? error;
                if (isEditing) {
                  await state.updateManagedUser(managedUser);
                } else {
                  error = await state.createManagedUser(
                    User(
                      id: '',
                      name: nameCtrl.text.trim(),
                      email: emailCtrl.text.trim().toLowerCase(),
                      role: role,
                      department: department,
                      campus: campus,
                      phone: phoneCtrl.text.trim().isEmpty
                          ? null
                          : phoneCtrl.text.trim(),
                      studentId: studentIdCtrl.text.trim().isEmpty
                          ? null
                          : studentIdCtrl.text.trim(),
                      courseProgram: courseProgramCtrl.text.trim().isEmpty
                          ? null
                          : courseProgramCtrl.text.trim(),
                      yearLevel: yearLevel,
                      skills: selectedSkills.toList(),
                    ),
                    passwordCtrl.text,
                  );
                }
                if (!dialogContext.mounted) return;
                if (error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(error),
                      backgroundColor: AppTheme.red500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.maroon,
                foregroundColor: Colors.white,
              ),
              child: Text(isEditing ? 'Save Changes' : 'Create Account'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    emailCtrl.dispose();
    passwordCtrl.dispose();
    phoneCtrl.dispose();
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Account updated.'
                : 'Account created. They need to open the verification link '
                      'emailed to them before they can log in.',
          ),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
      );
    }
  }

  Future<void> _showUserProfile(
    BuildContext context,
    AppState state,
    User user,
  ) async {
    final offices = state.officesForUser(user);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('User Profile'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatar(
                avatarUrl: user.avatar,
                initials: user.initials,
                size: 72,
              ),
              const SizedBox(height: 12),
              Text(
                user.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(user.role, style: const TextStyle(color: AppTheme.slate500)),
              const SizedBox(height: 20),
              _profileDetail('Email', user.email, Icons.email_outlined),
              _profileDetail(
                'Department',
                user.department ?? '—',
                Icons.business_outlined,
              ),
              _profileDetail(
                'Campus',
                user.campus ?? '—',
                Icons.location_city_outlined,
              ),
              _profileDetail(
                'Office',
                offices.isEmpty
                    ? 'Unassigned'
                    : offices.map((office) => office.name).join(', '),
                Icons.business_center_outlined,
              ),
              _profileDetail(
                'Phone',
                user.phone?.isEmpty ?? true ? '—' : user.phone!,
                Icons.phone_outlined,
              ),
              _profileDetail(
                'Student ID',
                user.studentId?.isEmpty ?? true ? '—' : user.studentId!,
                Icons.badge_outlined,
              ),
              _profileDetail(
                'Course/Program',
                user.courseProgram?.isEmpty ?? true ? '—' : user.courseProgram!,
                Icons.school_outlined,
              ),
              _profileDetail(
                'Year level',
                user.yearLevel?.isEmpty ?? true ? '—' : user.yearLevel!,
                Icons.timeline_outlined,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showUserDialog(context, state, user: user);
            },
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit Profile'),
          ),
        ],
      ),
    );
  }

  Widget _profileDetail(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.maroon),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _accountDropdown(
    String label,
    String value,
    List<String> values,
    ValueChanged<String> onChanged,
    IconData icon,
  ) {
    return DropdownButtonFormField<String>(
      value: values.contains(value) ? value : values.first,
      isExpanded: true,
      menuMaxHeight: 320,
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.maroon, size: 17),
      ),
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
    );
  }

  // ignore: unused_element
  void _showCreateDepartmentDialog(BuildContext context) {
    final state = context.read<AppState>();
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final headCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 440,
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
              // Header
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
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add_business_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create Department',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Add a new department to the system',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dialogField(
                      'Department Name',
                      nameCtrl,
                      Icons.business_outlined,
                    ),
                    const SizedBox(height: 14),
                    _dialogField(
                      'Department Code (e.g. CICS)',
                      codeCtrl,
                      Icons.tag_rounded,
                    ),
                    const SizedBox(height: 14),
                    _dialogField(
                      'Department Head',
                      headCtrl,
                      Icons.person_outline,
                    ),
                    const SizedBox(height: 20),

                    // Existing departments preview
                    const Text(
                      'EXISTING DEPARTMENTS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate400,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.slate50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.slate100),
                      ),
                      child: Column(
                        children: state.departments
                            .map(
                              (d) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.maroon,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        d,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.slate600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          final created = await state.addDepartment(name);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                created
                                    ? 'Department "$name" created!'
                                    : 'Could not create department "$name"',
                              ),
                              backgroundColor: created
                                  ? AppTheme.emerald500
                                  : AppTheme.amber500,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                        },
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text(
                          'Create Department',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
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

// ΓöÇΓöÇ Stat card ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _StatCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: color, width: 4)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate400,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1.1,
                    ),
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

// ΓöÇΓöÇ Col header ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

class _ColHeader extends StatelessWidget {
  final String text;
  final bool center;

  const _ColHeader(this.text, {this.center = false});
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: center ? TextAlign.center : TextAlign.left,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: AppTheme.slate400,
      letterSpacing: 0.7,
    ),
  );
}

// ΓöÇΓöÇ Account row ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
class _AccountRow extends StatefulWidget {
  final User user;
  final AppState state;
  final VoidCallback onEdit;
  final VoidCallback onView;
  final VoidCallback onDelete;
  final VoidCallback onArchiveToggle;
  final bool isMobile;
  const _AccountRow({
    required this.user,
    required this.state,
    required this.onEdit,
    required this.onView,
    required this.onDelete,
    required this.onArchiveToggle,
    this.isMobile = false,
  });

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  bool _hovered = false;

  Future<void> _pickAvatar() async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (!mounted) return;
      if (picked == null) {
        messenger?.showSnackBar(
          SnackBar(content: Text('No image selected.'),
        backgroundColor: AppTheme.amber500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
        );
        return;
      }

      final bytes = await picked.readAsBytes();
      final extension = picked.name.split('.').last.toLowerCase();
      final mimeType = extension == 'jpg' || extension == 'jpeg'
          ? 'image/jpeg'
          : 'image/$extension';
      final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';

      widget.state.updateUserAvatar(widget.user.id, dataUrl);
      messenger?.showSnackBar(
        SnackBar(content: Text('Profile picture updated.'),
        backgroundColor: AppTheme.emerald500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not update profile picture: $e'),
        backgroundColor: AppTheme.red500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
      );
    }
  }

  Color get _roleColor {
    switch (widget.user.role) {
      case 'Admin':
        return AppTheme.red500;
      case 'Head':
        return AppTheme.violet500;
      case 'Supervisor':
        return AppTheme.amber500;
      case 'Student Assistant':
        return AppTheme.blue500;
      case 'Student':
        return AppTheme.emerald500;
      default:
        return AppTheme.slate500;
    }
  }

  IconData get _roleIcon {
    switch (widget.user.role) {
      case 'Admin':
        return Icons.admin_panel_settings_outlined;
      case 'Head':
        return Icons.workspace_premium_outlined;
      case 'Supervisor':
        return Icons.supervisor_account_outlined;
      case 'Student Assistant':
        return Icons.handyman_outlined;
      case 'Student':
        return Icons.school_outlined;
      default:
        return Icons.person_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final isSelf = u.id == widget.state.currentUser?.id;

    if (widget.isMobile) {
      return _buildMobileCard(u, isSelf);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _hovered
            ? AppTheme.maroon50
            : (isSelf
                  ? AppTheme.gold100.withValues(alpha: 0.3)
                  : Colors.transparent),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Avatar
            isSelf
                ? GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        UserAvatar(
                          avatarUrl: u.avatar,
                          initials: u.initials,
                          size: 44,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: AppTheme.gold400,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : GestureDetector(
                    onTap: _pickAvatar,
                    child: Tooltip(
                      message: 'Edit profile picture',
                      child: UserAvatar(
                        avatarUrl: u.avatar,
                        initials: u.initials,
                        size: 44,
                      ),
                    ),
                  ),
            const SizedBox(width: 12),

            // Name + email
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        u.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.slate900,
                        ),
                      ),
                      if (isSelf) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.gold100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'You',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.gold400,
                            ),
                          ),
                        ),
                      ],
                      if (u.status == 'Archived') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.amber50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Archived',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.amber500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    u.email,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.slate500,
                    ),
                  ),
                ],
              ),
            ),

            // Role
            Expanded(
              flex: 2,
              child: isSelf
                  ? Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _roleColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(_roleIcon, size: 14, color: _roleColor),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            u.role,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _roleColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : _RoleDropdown(user: u, state: widget.state),
            ),

            // Department
            Expanded(
              flex: 3,
              child: Tooltip(
                message: u.department ?? '—',
                child: Text(
                  widget.state.departmentCodes[u.department] ??
                      u.department ??
                      '—',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.slate600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Campus
            Expanded(
              flex: 2,
              child: Text(
                u.campus?.replaceAll(' Campus', '') ?? 'ΓÇö',
                style: const TextStyle(fontSize: 13, color: AppTheme.slate600),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Actions
            SizedBox(
              width: 144,
              child: isSelf
                  ? IconButton(
                      onPressed: widget.onView,
                      icon: const Icon(
                        Icons.visibility_outlined,
                        size: 17,
                        color: AppTheme.slate400,
                      ),
                      tooltip: 'View profile',
                      padding: EdgeInsets.zero,
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: widget.onView,
                          icon: const Icon(
                            Icons.visibility_outlined,
                            size: 17,
                            color: AppTheme.slate400,
                          ),
                          tooltip: 'View profile',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                        IconButton(
                          onPressed: widget.onEdit,
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 17,
                            color: AppTheme.slate400,
                          ),
                          tooltip: 'Edit account',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                        IconButton(
                          onPressed: widget.onArchiveToggle,
                          icon: Icon(
                            u.status == 'Archived'
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                            size: 18,
                            color: u.status == 'Archived'
                                ? AppTheme.emerald500
                                : AppTheme.slate300,
                          ),
                          tooltip: u.status == 'Archived'
                              ? 'Restore account'
                              : 'Archive account',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                        IconButton(
                          onPressed: widget.onDelete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 17,
                            color: AppTheme.red500,
                          ),
                          tooltip: 'Delete account permanently',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ΓöÇΓöÇ Mobile: stacked card instead of the 4-column table row ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
  // FIX: cramming USER/ROLE/DEPARTMENT/ACTIONS into Expanded flex columns
  // on a ~320px-wide screen left no room for the role dropdown or
  // department text ΓÇö that was the overlapping "ROLE / DEPARTMENT /
  // ACTIONS" overflow in the screenshot. A stacked layout gives each
  // piece of info its own full-width line instead.
  Widget _buildMobileCard(User u, bool isSelf) {
    return Container(
      color: isSelf
          ? AppTheme.gold100.withValues(alpha: 0.3)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              isSelf
                  ? GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(
                        children: [
                          UserAvatar(
                            avatarUrl: u.avatar,
                            initials: u.initials,
                            size: 40,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: AppTheme.gold400,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : GestureDetector(
                      onTap: _pickAvatar,
                      child: Tooltip(
                        message: 'Edit profile picture',
                        child: UserAvatar(
                          avatarUrl: u.avatar,
                          initials: u.initials,
                          size: 40,
                        ),
                      ),
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            u.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppTheme.slate900,
                            ),
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.gold100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.gold400,
                              ),
                            ),
                          ),
                        ],
                        if (u.status == 'Archived') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.amber50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Archived',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.amber500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      u.email,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelf)
                IconButton(
                  onPressed: widget.onView,
                  icon: const Icon(
                    Icons.visibility_outlined,
                    size: 17,
                    color: AppTheme.slate400,
                  ),
                  tooltip: 'View profile',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                )
              else ...[
                IconButton(
                  onPressed: widget.onView,
                  icon: const Icon(
                    Icons.visibility_outlined,
                    size: 17,
                    color: AppTheme.slate400,
                  ),
                  tooltip: 'View profile',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  onPressed: widget.onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 17,
                    color: AppTheme.slate400,
                  ),
                  tooltip: 'Edit account',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  onPressed: widget.onArchiveToggle,
                  icon: Icon(
                    u.status == 'Archived'
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    size: 18,
                    color: u.status == 'Archived'
                        ? AppTheme.emerald500
                        : AppTheme.slate300,
                  ),
                  tooltip: u.status == 'Archived'
                      ? 'Restore account'
                      : 'Archive account',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                    color: AppTheme.red500,
                  ),
                  tooltip: 'Delete account permanently',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: isSelf
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _roleColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_roleIcon, size: 14, color: _roleColor),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              u.role,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _roleColor,
                              ),
                            ),
                          ),
                        ],
                      )
                    : _RoleDropdown(user: u, state: widget.state),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.business_outlined,
                size: 13,
                color: AppTheme.slate400,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: u.department ?? '—',
                  child: Text(
                    widget.state.departmentCodes[u.department] ??
                        u.department ??
                        '—',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.slate600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.location_city_outlined,
                size: 13,
                color: AppTheme.slate400,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  u.campus ?? 'ΓÇö',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.slate600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ΓöÇΓöÇ Role Dropdown ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
class _RoleDropdown extends StatelessWidget {
  final User user;
  final AppState state;
  const _RoleDropdown({required this.user, required this.state});

  Color _colorForRole(String role) {
    switch (role) {
      case 'Admin':
        return AppTheme.red500;
      case 'Head':
        return AppTheme.violet500;
      case 'Supervisor':
        return AppTheme.amber500;
      case 'Student Assistant':
        return AppTheme.blue500;
      case 'Student':
        return AppTheme.emerald500;
      default:
        return AppTheme.slate500;
    }
  }

  IconData _iconForRole(String role) {
    switch (role) {
      case 'Admin':
        return Icons.admin_panel_settings_outlined;
      case 'Head':
        return Icons.workspace_premium_outlined;
      case 'Supervisor':
        return Icons.supervisor_account_outlined;
      case 'Student Assistant':
        return Icons.handyman_outlined;
      case 'Student':
        return Icons.school_outlined;
      default:
        return Icons.person_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _colorForRole(user.role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: roleColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: roleColor.withValues(alpha: 0.25)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: user.role,
          isDense: true,
          icon: Icon(Icons.unfold_more_rounded, size: 14, color: roleColor),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: roleColor,
            fontFamily: 'Inter',
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          items: _roles.map((r) {
            final c = _colorForRole(r);
            return DropdownMenuItem(
              value: r,
              child: Row(
                children: [
                  Icon(_iconForRole(r), size: 14, color: c),
                  const SizedBox(width: 6),
                  Text(
                    r,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (newRole) async {
            if (newRole == null || newRole == user.role) return;

            // Build appropriate confirmation message
            String message =
                'Change ${user.name}\'s role from "${user.role}" to "$newRole"?';
            if ((user.role == 'Student' && newRole == 'Student Assistant') ||
                (user.role == 'Student Assistant' && newRole == 'Student')) {
              message +=
                  '\n\nAll notifications, applications, and other data will be preserved.';
            }

            final ok = await showConfirmDialog(
              context,
              title: 'Change Role',
              message: message,
              confirmLabel: 'Change',
              confirmColor: AppTheme.maroon,
            );
            if (ok) {
              state.changeUserRole(user.id, newRole);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${user.name}\'s role updated to $newRole. They will be notified of this change.',
                  ),
                  backgroundColor: AppTheme.emerald500,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  margin: const EdgeInsets.all(16),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}

// ΓöÇΓöÇ Admin Announcement Card ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
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
    final pendingCount = state.applications
        .where((a) => a.announcementId == ann.id && a.status == 'Pending')
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ann.isOpen
              ? AppTheme.maroon.withValues(alpha: 0.15)
              : AppTheme.slate200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ann.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: ann.isOpen ? AppTheme.emerald50 : AppTheme.slate100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: ann.isOpen
                        ? AppTheme.emerald500.withValues(alpha: 0.3)
                        : AppTheme.slate300,
                  ),
                ),
                child: Text(
                  ann.isOpen ? 'Open' : 'Closed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ann.isOpen ? AppTheme.emerald500 : AppTheme.slate400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ann.body,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.slate500,
              height: 1.5,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (ann.deadline != null)
                _Chip(
                  Icons.event_outlined,
                  'Due ${ann.deadline!}',
                  AppTheme.amber500,
                ),
              if (ann.slots != null) ...[
                const SizedBox(width: 8),
                _Chip(
                  Icons.people_outline,
                  '${ann.slots} slots',
                  AppTheme.blue500,
                ),
              ],
              const SizedBox(width: 8),
              _Chip(
                Icons.assignment_outlined,
                '$appCount applied',
                AppTheme.maroon,
              ),
              if (pendingCount > 0) ...[
                const SizedBox(width: 8),
                _Chip(
                  Icons.hourglass_empty_rounded,
                  '$pendingCount pending',
                  AppTheme.amber500,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              if (ann.isOpen)
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await showConfirmDialog(
                      ctx,
                      title: 'Close Announcement',
                      message:
                          'Stop accepting applications for "${ann.title}"?',
                      confirmLabel: 'Close',
                      confirmColor: AppTheme.slate700,
                    );
                    if (!ctx.mounted) return;
                    if (ok) state.closeAnnouncement(ann.id);
                  },
                  icon: const Icon(Icons.lock_outline, size: 14),
                  label: const Text(
                    'Close',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.slate600,
                    side: const BorderSide(color: AppTheme.slate300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    ctx,
                    title: 'Delete Announcement',
                    message: 'Delete "${ann.title}"?',
                    confirmLabel: 'Delete',
                    confirmColor: AppTheme.red500,
                  );
                  if (!ctx.mounted) return;
                  if (ok) {
                    state.deleteAnnouncement(ann.id);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Announcement deleted successfully',
                        ),
                        backgroundColor: AppTheme.red500,
                        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text(
                  'Delete',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.red500,
                  side: const BorderSide(color: AppTheme.red500),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
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

// ΓöÇΓöÇ Admin Application Card ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
class _AdminApplicationCard extends StatelessWidget {
  final Application app;
  final AppState state;
  final BuildContext ctx;
  const _AdminApplicationCard({
    required this.app,
    required this.state,
    required this.ctx,
  });

  Color get _color {
    switch (app.status) {
      case 'Approved':
        return AppTheme.emerald500;
      case 'Rejected':
        return AppTheme.red500;
      default:
        return AppTheme.amber500;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                initials: app.applicantName.isNotEmpty
                    ? app.applicantName[0].toUpperCase()
                    : '?',
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.applicantName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate900,
                      ),
                    ),
                    Text(
                      app.announcementTitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.slate500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Applied ${app.appliedAt}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.slate400,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  app.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _color,
                  ),
                ),
              ),
            ],
          ),
          if (app.skills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: app.skills
                  .map(
                    (s) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.slate100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.slate600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (app.status == 'Pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showApplicationDetails(context),
                  icon: const Icon(Icons.visibility_outlined, size: 14),
                  label: const Text(
                    'View Details',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.slate600,
                    side: const BorderSide(color: AppTheme.slate300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _reviewDialog(context, false),
                  icon: const Icon(Icons.close_rounded, size: 14),
                  label: const Text(
                    'Reject',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.red500,
                    side: const BorderSide(color: AppTheme.red500),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _reviewDialog(context, true),
                  icon: const Icon(Icons.check_rounded, size: 14),
                  label: const Text(
                    'Approve',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.emerald500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _reviewDialog(BuildContext context, bool approve) {
    final remarksCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          approve ? 'Approve Application' : 'Reject Application',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Applicant: ${app.applicantName}',
              style: const TextStyle(fontSize: 13, color: AppTheme.slate600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: remarksCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Remarks (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.maroon,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.slate500),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              state.updateApplicationStatus(
                app.id,
                approve ? 'Approved' : 'Rejected',
                remarks: remarksCtrl.text.trim().isEmpty
                    ? null
                    : remarksCtrl.text.trim(),
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Application ${approve ? "approved" : "rejected"}!',
                  ),
                  backgroundColor: approve
                      ? AppTheme.emerald500
                      : AppTheme.red500,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  margin: const EdgeInsets.all(16),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? AppTheme.emerald500 : AppTheme.red500,
              foregroundColor: Colors.white,
            ),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  void _showApplicationDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 750),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 30,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.maroon, AppTheme.maroonDark],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Application Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(4),
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
              // Content
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Applicant Info
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.slate50,
                            border: Border.all(color: AppTheme.slate200),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'APPLICANT',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slate400,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                app.applicantName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slate900,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'POSITION APPLIED FOR',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slate400,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                app.announcementTitle,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.slate700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'APPLIED DATE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slate400,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                app.appliedAt,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.slate600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Submitted Documents
                        if (app.submittedDocuments.isNotEmpty) ...[
                          const Text(
                            'SUBMITTED DOCUMENTS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slate400,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...app.submittedDocuments
                              .map(
                                (doc) => Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.emerald50,
                                    border: Border.all(
                                      color: AppTheme.emerald500.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle,
                                            color: AppTheme.emerald500,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  doc.requirementName,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.slate900,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  doc.fileName,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: AppTheme.slate600,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${(doc.fileSize ?? 0).toStringAsFixed(2)} MB ΓÇó ${doc.uploadedAt}',
                                            style: const TextStyle(
                                              fontSize: 9,
                                              color: AppTheme.slate500,
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              OutlinedButton.icon(
                                                onPressed:
                                                    (doc.bytes != null &&
                                                        doc.bytes!.isNotEmpty)
                                                    ? () =>
                                                          _downloadDocument(doc)
                                                    : null,
                                                icon: const Icon(
                                                  Icons.download_outlined,
                                                  size: 13,
                                                ),
                                                label: const Text(
                                                  'Download',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      (doc.bytes != null &&
                                                          doc.bytes!.isNotEmpty)
                                                      ? AppTheme.emerald500
                                                      : AppTheme.slate300,
                                                  side: BorderSide(
                                                    color:
                                                        (doc.bytes != null &&
                                                            doc
                                                                .bytes!
                                                                .isNotEmpty)
                                                        ? AppTheme.emerald500
                                                        : AppTheme.slate200,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.emerald500,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Uploaded',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          const SizedBox(height: 16),
                        ],
                        // Skills
                        if (app.skills.isNotEmpty) ...[
                          const Text(
                            'SKILLS / QUALIFICATIONS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slate400,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final s in app.skills)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.slate100,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    s,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.slate700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _downloadDocument(ApplicationDocument doc) {
    if (doc.bytes == null || doc.bytes!.isEmpty) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: const Text(
            'Document data not available - file may have been uploaded as preview only',
          ),
          backgroundColor: AppTheme.amber500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (kIsWeb) {
      _triggerWebDownload(doc.fileName, doc.bytes!);
    } else {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            'Document "${doc.fileName}" (${(doc.fileSize ?? 0).toStringAsFixed(2)} MB) is available',
          ),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _triggerWebDownload(String fileName, Uint8List bytes) {
    if (!kIsWeb) return;

    try {
      // For web, create a blob and trigger download with proper filename
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrl(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);

      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Downloading $fileName...'),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Unable to download: $e'),
          backgroundColor: AppTheme.amber500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
      );
    }
  }
}