import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/avatar_editor.dart';

class SpProfileScreen extends StatefulWidget {
  const SpProfileScreen({super.key});
  @override
  State<SpProfileScreen> createState() => _SpProfileScreenState();
}

class _SpProfileScreenState extends State<SpProfileScreen> {
  bool _isEditing = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    _nameCtrl = TextEditingController(text: user?.name ?? '');
    _phoneCtrl = TextEditingController(text: user?.phone ?? '');
    _addressCtrl = TextEditingController(text: user?.address ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  /// Picks an image, lets the user frame it, then stores the crop.
  ///
  /// There is no "are you sure" step before the picker any more: the editor
  /// is itself the confirmation, and the old sheet just added a tap.
  Future<void> _pickProfileImage() async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (!mounted || picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      final cropped = await showAvatarEditor(context, bytes);
      if (!mounted || cropped == null) return;

      await appState.updateProfile(
        avatar: 'data:image/png;base64,${base64Encode(cropped)}',
      );
      if (!mounted) return;

      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Profile picture updated.'),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          margin: EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not update profile picture: $e'),
          backgroundColor: AppTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;
    final myApps = state.myApplications;
    final isMobile = MediaQuery.of(context).size.width < 900;
    final hPad = MediaQuery.of(context).size.width < 600 ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page heading — identical to profile_screen
          Row(
            children: [
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.maroon,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${user?.name ?? 'Student'}'s Profile",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Text(
                      'Manage your personal information and account settings',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.slate400,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Cards — same layout as profile_screen (side-by-side on desktop)
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProfileCard(user, state),
                    const SizedBox(height: 20),
                    _buildInfoCard(user, state),
                    const SizedBox(height: 20),
                    _buildApplicationsCard(myApps),
                  ],
                )
              : Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 260,
                          child: _buildProfileCard(user, state),
                        ),
                        const SizedBox(width: 20),
                        Expanded(child: _buildInfoCard(user, state)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildApplicationsCard(myApps),
                  ],
                ),
        ],
      ),
    );
  }

  // ── Left: profile avatar card — matches profile_screen exactly ───────
  Widget _buildProfileCard(User? user, AppState state) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.maroon.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gradient banner
          Container(
            height: 72,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              gradient: LinearGradient(
                colors: [AppTheme.maroon, AppTheme.maroonDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Avatar overlapping banner
          Transform.translate(
            offset: const Offset(0, -44),
            child: Column(
              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: Stack(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.maroon.withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: UserAvatar(
                            avatarUrl: user?.avatar,
                            initials: user?.initials ?? '?',
                            size: 88,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _pickProfileImage,
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.gold400,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  user?.name ?? 'Student',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                    letterSpacing: -0.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.maroon, AppTheme.maroonDark],
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  child: Text(
                    state.role.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Contact info
          Transform.translate(
            offset: const Offset(0, -28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Container(height: 1, color: AppTheme.slate100),
                  const SizedBox(height: 14),
                  _contactRow(Icons.email_outlined, user?.email ?? '—'),
                  const SizedBox(height: 10),
                  _contactRow(
                    Icons.phone_outlined,
                    user?.phone?.isEmpty ?? true ? '—' : user!.phone!,
                  ),
                  const SizedBox(height: 10),
                  _contactRow(
                    Icons.location_on_outlined,
                    user?.address?.isEmpty ?? true ? '—' : user!.address!,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String value) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: AppTheme.maroon50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: AppTheme.maroon),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.slate600,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  // ── Right: Personal info card — mirrors profile_screen ───────────────
  Widget _buildInfoCard(User? user, AppState state) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header band
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: AppTheme.slate100)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.maroon50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.badge_outlined,
                          size: 16,
                          color: AppTheme.maroon,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Personal Information',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _editButton(state),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _isEditing ? _editingFields() : _viewFields(user),
                const SizedBox(height: 20),
                _skillsSection(
                  user,
                  state,
                  canEditSkills:
                      state.role != 'Admin' && state.role != 'Supervisor',
                ),
                const SizedBox(height: 20),
                _googleAccountButton(state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _googleAccountButton(AppState state) {
    final linked = state.isGoogleAccountLinked;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: linked
            ? null
            : () async {
                final error = await state.linkGoogleAccount();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error ?? 'Google account linked successfully.',
                    ),
                    backgroundColor: error == null
                        ? AppTheme.emerald500
                        : AppTheme.red500,
                    behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
                );
              },
        icon: Icon(linked ? Icons.check_circle_outline : Icons.link, size: 17),
        label: Text(linked ? 'Google Account Linked' : 'Link Google Account'),
      ),
    );
  }

  Widget _editButton(AppState state) {
    return GestureDetector(
      onTap: () {
        if (_isEditing) {
          state.updateProfile(
            name: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Profile updated!'),
              backgroundColor: AppTheme.emerald500,
              behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),),
          );
        }
        setState(() => _isEditing = !_isEditing);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _isEditing ? AppTheme.emerald500 : AppTheme.maroon,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: (_isEditing ? AppTheme.emerald500 : AppTheme.maroon)
                  .withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isEditing ? Icons.check_rounded : Icons.edit_outlined,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              _isEditing ? 'Save Changes' : 'Edit Profile',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skillsSection(
    User? user,
    AppState state, {
    required bool canEditSkills,
  }) {
    if (user == null) return const SizedBox.shrink();
    final selectedSkills = {...state.skillsForUser(user)};
    final availableSkills = {...state.skills, ...selectedSkills}.toList()
      ..sort();
    return StatefulBuilder(
      builder: (context, setState) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        leading: const Icon(Icons.stars_outlined, color: AppTheme.maroon),
        title: const Text(
          'Skills & Qualifications',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${selectedSkills.length} selected',
          style: const TextStyle(fontSize: 12, color: AppTheme.slate400),
        ),
        children: availableSkills.isEmpty
            ? [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No saved skills available.',
                    style: TextStyle(color: AppTheme.slate400),
                  ),
                ),
              ]
            : availableSkills
                  .map(
                    (skill) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(skill),
                      value: selectedSkills.contains(skill),
                      onChanged: !canEditSkills
                          ? null
                          : (checked) async {
                              setState(() {
                                if (checked == true) {
                                  selectedSkills.add(skill);
                                } else {
                                  selectedSkills.remove(skill);
                                }
                              });
                              await state.updateProfile(
                                skills: selectedSkills.toList(),
                              );
                            },
                    ),
                  )
                  .toList(),
      ),
    );
  }

  Widget _viewFields(User? user) => LayoutBuilder(
    builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 520;
      return Column(
        children: [
          if (isNarrow) ...[
            _readonlyField(
              'FULL NAME',
              user?.name ?? '—',
              Icons.person_outline,
            ),
            const SizedBox(height: 16),
            _readonlyField(
              'EMAIL ADDRESS',
              user?.email ?? '—',
              Icons.email_outlined,
            ),
            const SizedBox(height: 16),
            _readonlyField(
              'PHONE NUMBER',
              user?.phone?.isEmpty ?? true ? '—' : user!.phone!,
              Icons.phone_outlined,
            ),
            const SizedBox(height: 16),
            _readonlyField(
              'DEPARTMENT',
              user?.department ?? '—',
              Icons.business_outlined,
            ),
            const SizedBox(height: 16),
            _readonlyField(
              'CAMPUS',
              user?.campus ?? '—',
              Icons.location_city_outlined,
            ),
            const SizedBox(height: 16),
            _readonlyField(
              'STUDENT ID',
              user?.studentId?.isEmpty ?? true ? '—' : user!.studentId!,
              Icons.badge_outlined,
            ),
            const SizedBox(height: 16),
            _readonlyField(
              'COURSE/PROGRAM',
              user?.courseProgram?.isEmpty ?? true ? '—' : user!.courseProgram!,
              Icons.school_outlined,
            ),
            const SizedBox(height: 16),
            _readonlyField(
              'YEAR LEVEL',
              user?.yearLevel?.isEmpty ?? true ? '—' : user!.yearLevel!,
              Icons.timeline_outlined,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _readonlyField(
                    'FULL NAME',
                    user?.name ?? '—',
                    Icons.person_outline,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _readonlyField(
                    'EMAIL ADDRESS',
                    user?.email ?? '—',
                    Icons.email_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _readonlyField(
                    'PHONE NUMBER',
                    user?.phone?.isEmpty ?? true ? '—' : user!.phone!,
                    Icons.phone_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _readonlyField(
                    'DEPARTMENT',
                    user?.department ?? '—',
                    Icons.business_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _readonlyField(
                    'CAMPUS',
                    user?.campus ?? '—',
                    Icons.location_city_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _readonlyField(
                    'HOME ADDRESS',
                    user?.address?.isEmpty ?? true ? '—' : user!.address!,
                    Icons.location_on_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _readonlyField(
                    'STUDENT ID',
                    user?.studentId?.isEmpty ?? true ? '—' : user!.studentId!,
                    Icons.badge_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _readonlyField(
                    'COURSE/PROGRAM',
                    user?.courseProgram?.isEmpty ?? true ? '—' : user!.courseProgram!,
                    Icons.school_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _readonlyField(
              'YEAR LEVEL',
              user?.yearLevel?.isEmpty ?? true ? '—' : user!.yearLevel!,
              Icons.timeline_outlined,
            ),
          ],
          if (isNarrow) ...[
            const SizedBox(height: 16),
            _readonlyField(
              'HOME ADDRESS',
              user?.address?.isEmpty ?? true ? '—' : user!.address!,
              Icons.location_on_outlined,
            ),
          ],
        ],
      );
    },
  );

  Widget _readonlyField(String label, String value, IconData icon) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppTheme.slate400,
          letterSpacing: 1.0,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.slate50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.slate400),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.slate700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _editingFields() => LayoutBuilder(
    builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 520;
      return Column(
        children: [
          _editField('Full Name', _nameCtrl, Icons.person_outline),
          const SizedBox(height: 14),
          if (isNarrow) ...[
            _editField('Phone Number', _phoneCtrl, Icons.phone_outlined),
            const SizedBox(height: 14),
            _editField(
              'Home Address',
              _addressCtrl,
              Icons.location_on_outlined,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _editField(
                    'Phone Number',
                    _phoneCtrl,
                    Icons.phone_outlined,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _editField(
                    'Home Address',
                    _addressCtrl,
                    Icons.location_on_outlined,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );

  Widget _editField(String label, TextEditingController ctrl, IconData icon) =>
      TextField(
        controller: ctrl,
        style: const TextStyle(
          fontSize: 13,
          color: AppTheme.slate800,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
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
            vertical: 13,
          ),
        ),
      );

  // ── Application history card ─────────────────────────────────────────
  Widget _buildApplicationsCard(List<Application> apps) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: AppTheme.slate100)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.maroon50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.assignment_outlined,
                    size: 16,
                    color: AppTheme.maroon,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'My Applications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate900,
                  ),
                ),
                const SizedBox(width: 8),
                if (apps.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.maroon,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${apps.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (apps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: AppTheme.slate100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.assignment_outlined,
                      size: 26,
                      color: AppTheme.slate300,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'No applications yet',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slate400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Center(
                    child: Text(
                      'Applications you submit will appear here.',
                      style: TextStyle(fontSize: 12, color: AppTheme.slate300),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: apps.length,
              separatorBuilder: (_, __) =>
                  Container(height: 1, color: AppTheme.slate100),
              itemBuilder: (_, i) => _AppRow(application: apps[i]),
            ),
        ],
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  final Application application;
  const _AppRow({required this.application});

  Color get _statusColor {
    switch (application.status) {
      case 'Approved':
        return AppTheme.emerald500;
      case 'Waitlisted':
        return AppTheme.blue500;
      case 'Rejected':
        return AppTheme.red500;
      default:
        return AppTheme.amber500;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.assignment_outlined,
              size: 16,
              color: _statusColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  application.announcementTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Applied ${application.appliedAt}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate400,
                  ),
                ),
                if (application.remarks != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Remarks: ${application.remarks}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slate500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              application.status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
