import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'shared_widgets.dart';

/// Shared building blocks for the two profile screens.
///
/// The staff profile and the student-portal profile are the same page with a
/// different set of cards, and used to be maintained as two copies that had
/// already drifted. Everything visual lives here so they cannot drift again.

const double _cardRadius = 20;
const double _avatarSize = 96;
const double _bannerHeight = 84;

/// Page title with the maroon rule and gold tick, matching the section
/// headings used elsewhere in the app.
class ProfilePageHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isMobile;

  const ProfilePageHeading({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 38,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.maroon, AppTheme.gold400],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 19 : 23,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.slate400,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// White card with a header band, used for every panel on the page.
class ProfileCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ProfileCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: AppTheme.slate50,
              // Gold underline, the same accent the app bar carries.
              border: Border(
                bottom: BorderSide(color: AppTheme.gold400, width: 2),
              ),
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
                      child: Icon(icon, size: 16, color: AppTheme.maroon),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate900,
                        ),
                      ),
                    ),
                  ],
                );

                if (trailing == null) return label;

                // Below this the label and the action cannot share a line
                // without the action being pushed off the card.
                if (constraints.maxWidth < 340) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerLeft, child: trailing!),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                );
              },
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// The avatar / name / role / contact card down the left of the page.
class ProfileIdentityCard extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final String name;
  final String role;
  final VoidCallback onEditPhoto;
  final List<ProfileContact> contacts;

  const ProfileIdentityCard({
    super.key,
    required this.avatarUrl,
    required this.initials,
    required this.name,
    required this.role,
    required this.onEditPhoto,
    required this.contacts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner with the avatar hanging over its lower edge. A Stack with
          // clipBehavior none rather than a negative Transform, so the
          // following widgets keep their natural positions.
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                height: _bannerHeight,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.maroon, AppTheme.maroonDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(
                    bottom: BorderSide(color: AppTheme.gold400, width: 3),
                  ),
                ),
              ),
              Positioned(
                top: _bannerHeight - _avatarSize / 2,
                child: _AvatarWithEditButton(
                  avatarUrl: avatarUrl,
                  initials: initials,
                  onEditPhoto: onEditPhoto,
                ),
              ),
            ],
          ),
          // Room for the half of the avatar that overhangs the banner.
          const SizedBox(height: _avatarSize / 2 + 14),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Column(
              children: [
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                    letterSpacing: -0.2,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.maroon, AppTheme.maroonDark],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                if (contacts.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: AppTheme.slate100),
                  const SizedBox(height: 16),
                  for (var i = 0; i < contacts.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _ContactRow(contact: contacts[i]),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileContact {
  final IconData icon;
  final String value;

  const ProfileContact(this.icon, this.value);
}

class _ContactRow extends StatelessWidget {
  final ProfileContact contact;

  const _ContactRow({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppTheme.maroon50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(contact.icon, size: 14, color: AppTheme.maroon),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            contact.value,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.slate600,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AvatarWithEditButton extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final VoidCallback onEditPhoto;

  const _AvatarWithEditButton({
    required this.avatarUrl,
    required this.initials,
    required this.onEditPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _avatarSize,
      height: _avatarSize,
      child: Stack(
        children: [
          Container(
            width: _avatarSize,
            height: _avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.maroon.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: UserAvatar(
                avatarUrl: avatarUrl,
                initials: initials,
                size: _avatarSize,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onEditPhoto,
                borderRadius: BorderRadius.circular(999),
                child: Tooltip(
                  message: 'Change photo',
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.maroon,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One read-only field in the details grid.
class ProfileFieldData {
  final String label;
  final String value;
  final IconData icon;

  const ProfileFieldData(this.label, this.value, this.icon);
}

/// Read-only fields, two per row where there is room and one per row below
/// that. The old layout was a fixed two-column Row at every width, which
/// squeezed both fields to about 130px on a phone.
class ProfileFieldGrid extends StatelessWidget {
  static const double _twoColumnMin = 520;

  final List<ProfileFieldData> fields;

  const ProfileFieldGrid({super.key, required this.fields});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final columns = constraints.maxWidth >= _twoColumnMin ? 2 : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final field in fields)
              SizedBox(width: width, child: _ReadonlyField(field: field)),
          ],
        );
      },
    );
  }
}

class _ReadonlyField extends StatelessWidget {
  final ProfileFieldData field;

  const _ReadonlyField({required this.field});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          field.label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9.5,
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
              Icon(field.icon, size: 14, color: AppTheme.slate400),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  field.value,
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
}

/// The Edit / Save toggle in a card header.
class ProfileEditButton extends StatelessWidget {
  final bool isEditing;
  final VoidCallback onPressed;

  const ProfileEditButton({
    super.key,
    required this.isEditing,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = isEditing ? AppTheme.emerald500 : AppTheme.maroon;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.28),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isEditing ? Icons.check_rounded : Icons.edit_outlined,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                isEditing ? 'Save changes' : 'Edit profile',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Editable field, styled to line up with [ProfileFieldGrid]'s read-only one.
class ProfileTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;

  const ProfileTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.slate400,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.slate800,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: Icon(icon, color: AppTheme.maroon, size: 17),
            prefixIconConstraints: const BoxConstraints(minWidth: 38),
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
              horizontal: 12,
              vertical: 13,
            ),
          ),
        ),
      ],
    );
  }
}
