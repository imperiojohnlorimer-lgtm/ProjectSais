import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

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

  Future<void> _pickProfileImage() async {
    final shouldContinue = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppTheme.maroon.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.photo_camera_outlined,
                      size: 28,
                      color: AppTheme.maroon,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Change your profile photo?',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick a new image from your gallery to refresh your account look.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.slate500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        icon: const Icon(Icons.arrow_forward_ios, size: 14),
                        label: const Text('Continue'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (shouldContinue != true) return;

    final appState = context.read<AppState>();
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
            SnackBar(
            content: Text('No image selected.'),
            backgroundColor: AppTheme.amber500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            margin: EdgeInsets.all(16),
          ),
        );
        return;
      }

      final bytes = await picked.readAsBytes();
      final dataUrl =
          'data:image/${picked.name.split('.').last.toLowerCase()};base64,${base64Encode(bytes)}';
      appState.updateProfile(avatar: dataUrl);

      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Profile picture updated.',
            style: TextStyle(color: Colors.white),
          ),
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
          content: Text(
            'Could not update profile picture: $e',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: AppTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
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
    final isMobile = MediaQuery.of(context).size.width < 900;

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
          // ── Page heading ──────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 32,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: AppTheme.maroon,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // FIX: wrap in Expanded so the title/subtitle text wraps and
              // shrinks to the available width instead of overflowing past
              // the screen edge on narrow devices.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${user.name}'s Profile",
                      style: TextStyle(
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage your personal information and account settings',
                      style: const TextStyle(
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
          SizedBox(height: isMobile ? 20 : 28),

          // ── Cards ─────────────────────────────────────────────
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProfileCard(user, state),
                    const SizedBox(height: 20),
                    _buildPersonalInfoCard(user, state),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 260, child: _buildProfileCard(user, state)),
                    const SizedBox(width: 20),
                    Expanded(child: _buildPersonalInfoCard(user, state)),
                  ],
                ),
        ],
      ),
    );
  }

  // ── Left: Profile card ────────────────────────────────────────────
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
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              gradient: const LinearGradient(
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
                  user?.name ?? 'User',
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
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.maroon, AppTheme.maroonDark],
                    ),
                    borderRadius: BorderRadius.circular(20),
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

          // Contact info — pulled up into the negative-space left by transform
          Transform.translate(
            offset: const Offset(0, -28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _divider(),
                  const SizedBox(height: 14),
                  _contactRow(Icons.email_outlined, user?.email ?? '—'),
                  const SizedBox(height: 10),
                  _contactRow(
                    Icons.phone_outlined,
                    (user?.phone?.isEmpty ?? true) ? '—' : user!.phone!,
                  ),
                  const SizedBox(height: 10),
                  _contactRow(
                    Icons.location_on_outlined,
                    (user?.address?.isEmpty ?? true) ? '—' : user!.address!,
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

  Widget _divider() => Container(height: 1, color: AppTheme.slate100);

  Widget _contactRow(IconData icon, String value) {
    return Row(
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
  }

  // ── Right: Personal info card ─────────────────────────────────────
  Widget _buildPersonalInfoCard(User? user, AppState state) {
    final isMobile = MediaQuery.of(context).size.width < 900;
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
          // FIX: on narrow screens the label + Edit button used to sit in
          // one Row with no Expanded/Flexible, so long labels pushed the
          // button past the card edge (the overflow stripes). LayoutBuilder
          // now switches to a stacked layout below a breakpoint.
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: 18,
            ),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border(bottom: BorderSide(color: AppTheme.slate100)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final label = Row(
                  mainAxisSize: MainAxisSize.min,
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
                    const Flexible(
                      child: Text(
                        'Personal Information',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate900,
                        ),
                      ),
                    ),
                  ],
                );

                if (constraints.maxWidth < 340) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label,
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _editButton(),
                      ),
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 12),
                    _editButton(),
                  ],
                );
              },
            ),
          ),

          // Fields
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Column(
              children: [
                _isEditing ? _editingFields() : _viewFields(user, state),
                const SizedBox(height: 20),
                _skillsSection(
                  user!,
                  state,
                  canEditSkills:
                      state.role == 'Head' || state.role == 'Supervisor',
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

  Widget _skillsSection(
    User user,
    AppState state, {
    required bool canEditSkills,
  }) {
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

  Widget _editButton() {
    return GestureDetector(
      onTap: () {
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

  Widget _viewFields(User? user, AppState state) {
    final officeNames = state.currentUserOffices
        .map((office) => office.name)
        .join(', ');
    return Column(
      children: [
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
                'DEPARTMENT',
                user?.department ?? '—',
                Icons.business_outlined,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _readonlyField(
                'OFFICE',
                officeNames.isEmpty ? 'Unassigned' : officeNames,
                Icons.business_center_outlined,
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
                (user?.phone?.isEmpty ?? true) ? '—' : user!.phone!,
                Icons.phone_outlined,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _readonlyField(
                'CAMPUS',
                user?.campus ?? '—',
                Icons.location_city_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _readonlyField(
                'STUDENT ID',
                (user?.studentId?.isEmpty ?? true) ? '—' : user!.studentId!,
                Icons.badge_outlined,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _readonlyField(
                'COURSE/PROGRAM',
                (user?.courseProgram?.isEmpty ?? true) ? '—' : user!.courseProgram!,
                Icons.school_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _readonlyField(
                'YEAR LEVEL',
                (user?.yearLevel?.isEmpty ?? true) ? '—' : user!.yearLevel!,
                Icons.timeline_outlined,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _readonlyField(
                'HOME ADDRESS',
                (user?.address?.isEmpty ?? true) ? '—' : user!.address!,
                Icons.location_on_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _readonlyField(
                'SA ID',
                (user?.saId?.isEmpty ?? true) ? '—' : user!.saId!,
                Icons.badge_outlined,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }

  Widget _readonlyField(String label, String value, IconData icon) {
    return Column(
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
  }

  Widget _editingFields() {
    return Column(
      children: [
        _editField('Full Name', _nameCtrl, Icons.person_outline),
        const SizedBox(height: 14),
        _editField('Phone Number', _phoneCtrl, Icons.phone_outlined),
        const SizedBox(height: 14),
        _editField('Home Address', _addressCtrl, Icons.location_on_outlined),
      ],
    );
  }

  Widget _editField(String label, TextEditingController ctrl, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(
        fontSize: 13,
        color: AppTheme.slate800,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 12,
          color: AppTheme.slate500,
          fontWeight: FontWeight.w600,
        ),
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
  }
}