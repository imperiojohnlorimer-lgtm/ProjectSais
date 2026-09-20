import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_editor.dart';
import '../../widgets/profile_widgets.dart';

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
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
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

  void _toggleEditing(AppState state) {
    if (_isEditing) {
      state.updateProfile(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated.'),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
    setState(() => _isEditing = !_isEditing);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;
    final myApps = state.myApplications;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 900;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: width < 600 ? 16 : 32,
        vertical: isMobile ? 20 : 28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfilePageHeading(
            title: "${user?.name ?? 'Student'}'s Profile",
            subtitle: 'Manage your personal information and account settings',
            isMobile: isMobile,
          ),
          SizedBox(height: isMobile ? 20 : 28),

          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _identityCard(user, state),
                const SizedBox(height: 20),
                _detailsCard(user, state),
                const SizedBox(height: 20),
                _accountCard(user, state),
                const SizedBox(height: 20),
                _applicationsCard(myApps),
              ],
            )
          else
            Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 280,
                      child: Column(
                        children: [
                          _identityCard(user, state),
                          const SizedBox(height: 20),
                          _accountCard(user, state),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(child: _detailsCard(user, state)),
                  ],
                ),
                const SizedBox(height: 20),
                _applicationsCard(myApps),
              ],
            ),
        ],
      ),
    );
  }

  Widget _identityCard(User? user, AppState state) {
    return ProfileIdentityCard(
      avatarUrl: user?.avatar,
      initials: user?.initials ?? '?',
      name: user?.name ?? 'Student',
      role: state.role,
      onEditPhoto: _pickProfileImage,
      contacts: [
        ProfileContact(Icons.email_outlined, user?.email ?? '—'),
        ProfileContact(
          Icons.phone_outlined,
          (user?.phone?.isEmpty ?? true) ? '—' : user!.phone!,
        ),
        ProfileContact(
          Icons.location_on_outlined,
          (user?.address?.isEmpty ?? true) ? '—' : user!.address!,
        ),
      ],
    );
  }

  Widget _detailsCard(User? user, AppState state) {
    return ProfileCard(
      icon: Icons.badge_outlined,
      title: 'Personal Information',
      trailing: ProfileEditButton(
        isEditing: _isEditing,
        onPressed: () => _toggleEditing(state),
      ),
      child: _isEditing ? _editingFields() : _viewFields(user),
    );
  }

  Widget _viewFields(User? user) {
    String orDash(String? value) =>
        (value == null || value.isEmpty) ? '—' : value;

    return ProfileFieldGrid(
      fields: [
        ProfileFieldData('Full name', orDash(user?.name), Icons.person_outline),
        ProfileFieldData(
          'Email address',
          orDash(user?.email),
          Icons.email_outlined,
        ),
        ProfileFieldData(
          'Phone number',
          orDash(user?.phone),
          Icons.phone_outlined,
        ),
        ProfileFieldData(
          'Department',
          orDash(user?.department),
          Icons.business_outlined,
        ),
        ProfileFieldData(
          'Campus',
          orDash(user?.campus),
          Icons.location_city_outlined,
        ),
        ProfileFieldData(
          'Home address',
          orDash(user?.address),
          Icons.location_on_outlined,
        ),
        ProfileFieldData(
          'Student ID',
          orDash(user?.studentId),
          Icons.badge_outlined,
        ),
        ProfileFieldData(
          'Course/Program',
          orDash(user?.courseProgram),
          Icons.school_outlined,
        ),
        ProfileFieldData(
          'Year level',
          orDash(user?.yearLevel),
          Icons.timeline_outlined,
        ),
      ],
    );
  }

  Widget _editingFields() {
    return Column(
      children: [
        ProfileTextField(
          label: 'Full name',
          controller: _nameCtrl,
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 16),
        ProfileTextField(
          label: 'Phone number',
          controller: _phoneCtrl,
          icon: Icons.phone_outlined,
        ),
        const SizedBox(height: 16),
        ProfileTextField(
          label: 'Home address',
          controller: _addressCtrl,
          icon: Icons.location_on_outlined,
        ),
      ],
    );
  }

  /// Skills and the Google link are about the account rather than the person,
  /// so they sit in their own card instead of trailing the details.
  Widget _accountCard(User? user, AppState state) {
    return ProfileCard(
      icon: Icons.manage_accounts_outlined,
      title: 'Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _skillsSection(user, state),
          const SizedBox(height: 12),
          _googleAccountButton(state),
        ],
      ),
    );
  }

  /// Read-only here: a student can see their skills, but a Head or Supervisor
  /// sets them during screening.
  Widget _skillsSection(User? user, AppState state) {
    if (user == null) return const SizedBox.shrink();
    final selectedSkills = {...state.skillsForUser(user)};
    final availableSkills = {...state.skills, ...selectedSkills}.toList()
      ..sort();

    return Theme(
      // Drops the ExpansionTile's default divider lines, which cut right
      // across the card.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
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
                      activeColor: AppTheme.maroon,
                      title: Text(skill, style: const TextStyle(fontSize: 13)),
                      value: selectedSkills.contains(skill),
                      onChanged: null,
                    ),
                  )
                  .toList(),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              },
        icon: Icon(linked ? Icons.check_circle_outline : Icons.link, size: 17),
        label: Text(linked ? 'Google account linked' : 'Link Google account'),
      ),
    );
  }

  Widget _applicationsCard(List<Application> apps) {
    return ProfileCard(
      icon: Icons.assignment_outlined,
      title: 'My Applications',
      padding: EdgeInsets.zero,
      trailing: apps.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
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
      child: apps.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: _EmptyApplications(),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: apps.length,
              separatorBuilder: (_, _) =>
                  Container(height: 1, color: AppTheme.slate100),
              itemBuilder: (_, i) => _AppRow(application: apps[i]),
            ),
    );
  }
}

class _EmptyApplications extends StatelessWidget {
  const _EmptyApplications();

  @override
  Widget build(BuildContext context) {
    return Column(
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
        const Text(
          'No applications yet',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate400,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Applications you submit will appear here.',
          style: TextStyle(fontSize: 12, color: AppTheme.slate300),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
          const SizedBox(width: 10),
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
