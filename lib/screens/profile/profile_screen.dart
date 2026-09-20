import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_editor.dart';
import '../../widgets/profile_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  bool _hasInitializedControllers = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitializedControllers) {
      final user = context.watch<AppState>().currentUser;
      if (user != null) {
        _nameCtrl.text = user.name;
        _phoneCtrl.text = user.phone ?? '';
        _addressCtrl.text = user.address ?? '';
        _hasInitializedControllers = true;
      }
    }
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

  void _toggleEditing() {
    if (_isEditing) {
      final state = context.read<AppState>();
      state.updateProfile(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        yearLevel: state.currentUser?.yearLevel,
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
    final isMobile = MediaQuery.sizeOf(context).width < 900;

    if (user == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 20 : 32,
            vertical: isMobile ? 40 : 80,
          ),
          child: Text(
            'Loading profile... please wait.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              color: AppTheme.slate600,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: isMobile ? 20 : 28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfilePageHeading(
            title: "${user.name}'s Profile",
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
              ],
            )
          else
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
        ],
      ),
    );
  }

  Widget _identityCard(User user, AppState state) {
    return ProfileIdentityCard(
      avatarUrl: user.avatar,
      initials: user.initials,
      name: user.name,
      role: state.role,
      onEditPhoto: _pickProfileImage,
      contacts: [
        ProfileContact(Icons.email_outlined, user.email),
        ProfileContact(
          Icons.phone_outlined,
          (user.phone?.isEmpty ?? true) ? '—' : user.phone!,
        ),
        ProfileContact(
          Icons.location_on_outlined,
          (user.address?.isEmpty ?? true) ? '—' : user.address!,
        ),
      ],
    );
  }

  Widget _detailsCard(User user, AppState state) {
    return ProfileCard(
      icon: Icons.badge_outlined,
      title: 'Personal Information',
      trailing: ProfileEditButton(
        isEditing: _isEditing,
        onPressed: _toggleEditing,
      ),
      child: _isEditing ? _editingFields() : _viewFields(user, state),
    );
  }

  Widget _viewFields(User user, AppState state) {
    final offices = state.currentUserOffices.map((o) => o.name).join(', ');
    String orDash(String? value) =>
        (value == null || value.isEmpty) ? '—' : value;

    return ProfileFieldGrid(
      fields: [
        ProfileFieldData('Full name', user.name, Icons.person_outline),
        ProfileFieldData('Email address', user.email, Icons.email_outlined),
        ProfileFieldData(
          'Department',
          orDash(user.department),
          Icons.business_outlined,
        ),
        ProfileFieldData(
          'Office',
          offices.isEmpty ? 'Unassigned' : offices,
          Icons.business_center_outlined,
        ),
        ProfileFieldData(
          'Phone number',
          orDash(user.phone),
          Icons.phone_outlined,
        ),
        ProfileFieldData(
          'Campus',
          orDash(user.campus),
          Icons.location_city_outlined,
        ),
        ProfileFieldData(
          'Student ID',
          orDash(user.studentId),
          Icons.badge_outlined,
        ),
        ProfileFieldData(
          'Course/Program',
          orDash(user.courseProgram),
          Icons.school_outlined,
        ),
        ProfileFieldData(
          'Year level',
          orDash(user.yearLevel),
          Icons.timeline_outlined,
        ),
        ProfileFieldData(
          'Home address',
          orDash(user.address),
          Icons.location_on_outlined,
        ),
        ProfileFieldData('SA ID', orDash(user.saId), Icons.badge_outlined),
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
  Widget _accountCard(User user, AppState state) {
    return ProfileCard(
      icon: Icons.manage_accounts_outlined,
      title: 'Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _skillsSection(
            user,
            state,
            canEditSkills: state.role == 'Head' || state.role == 'Supervisor',
          ),
          const SizedBox(height: 12),
          _googleAccountButton(state),
        ],
      ),
    );
  }

  Widget _skillsSection(
    User user,
    AppState state, {
    required bool canEditSkills,
  }) {
    final selectedSkills = {...state.skillsForUser(user)};
    final availableSkills = {...state.skills, ...selectedSkills}.toList()
      ..sort();

    return StatefulBuilder(
      builder: (context, setState) => Theme(
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
                        title: Text(
                          skill,
                          style: const TextStyle(fontSize: 13),
                        ),
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
}
