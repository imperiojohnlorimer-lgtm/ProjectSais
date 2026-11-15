import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/office_picture.dart';
import '../../widgets/shared_widgets.dart';
import '../student_portal/student_page_widgets.dart';

/// A Student Assistant's page for their own office: what it does, where it
/// is, who supervises it and what it looks for. The Head fills in the About
/// and Location on the Offices page. Names only: no contact details and no
/// list of the office's other assistants.
class MyOfficeScreen extends StatelessWidget {
  /// Gets a location picture's bytes. Tests pass their own.
  final OfficePictureLoader? pictureLoader;

  const MyOfficeScreen({super.key, @visibleForTesting this.pictureLoader});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 600;
    final hPad = isMobile ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StudentPageTitle(
                title: 'My Office',
                subtitle: 'Where you work and who supervises it.',
              ),
              const SizedBox(height: 24),
              ..._content(state),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(AppState state) {
    // Before the offices arrive, or when they couldn't be read, "not placed
    // yet" could be wrong.
    if (state.failedLoads.contains('Offices')) {
      return const [
        _Notice(
          icon: Icons.cloud_off_outlined,
          text: "Couldn't load your office. Try again later.",
        ),
      ];
    }
    if (!state.isLoaded('Offices')) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final user = state.currentUser;
    final offices = state.currentUserOffices;
    if (offices.isNotEmpty) {
      return [
        for (var i = 0; i < offices.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _OfficeCard(office: offices[i], pictureLoader: pictureLoader),
        ],
      ];
    }

    final inactive = user == null
        ? const <Office>[]
        : state.offices
              .where((o) => !o.isActive && o.hasAssistant(user.id, user.name))
              .toList();
    return [
      if (inactive.isEmpty)
        const _Notice(
          icon: Icons.hourglass_empty_rounded,
          text:
              "You're not placed in an office yet. The Head of Student "
              "Assistantship will assign you, and you'll get a notification "
              'when it is done.',
        )
      else
        _Notice(
          icon: Icons.pause_circle_outline_rounded,
          text:
              'Your office (${inactive.first.name}) is currently inactive. '
              'Ask the Head of Student Assistantship.',
        ),
    ];
  }
}

class _OfficeCard extends StatefulWidget {
  final Office office;
  final OfficePictureLoader? pictureLoader;
  const _OfficeCard({required this.office, this.pictureLoader});

  @override
  State<_OfficeCard> createState() => _OfficeCardState();
}

class _OfficeCardState extends State<_OfficeCard> {
  Office get office => widget.office;
  OfficePictureLoader? get pictureLoader => widget.pictureLoader;

  @override
  void initState() {
    super.initState();
    _loadPictures();
  }

  @override
  void didUpdateWidget(_OfficeCard old) {
    super.didUpdateWidget(old);
    final before = [for (final s in old.office.supervisorEntries) s.id];
    final now = [for (final s in office.supervisorEntries) s.id];
    if (before.join(',') != now.join(',')) _loadPictures();
  }

  /// The supervisors' pictures come from their cards (a profile is not
  /// readable here); without one, initials show.
  void _loadPictures() {
    final ids = [for (final s in office.supervisorEntries) s.id];
    // After the first frame: this runs while the page is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadSupervisorCards(ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    final code = office.code.trim();
    final supervisors = office.supervisorEntries;
    final avatars = context.select<AppState, Map<String, String>>(
      (s) => s.supervisorAvatars,
    );
    final skills = [
      for (final skill in office.requiredSkills)
        if (skill.trim().isNotEmpty) skill.trim(),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: studentCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.maroon,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.apartment_outlined,
                  size: 21,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      office.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    if (code.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.slate100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const StudentSectionLabel('ABOUT'),
          const SizedBox(height: 6),
          _Text(
            office.about.trim(),
            empty: "The Head hasn't added a description yet.",
          ),
          const SizedBox(height: 18),
          const StudentSectionLabel('LOCATION'),
          const SizedBox(height: 6),
          _Text(
            office.location.trim(),
            empty: "The Head hasn't added a location yet.",
            icon: Icons.place_outlined,
          ),
          if (office.locationImagePath.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            OfficePicture(
              path: office.locationImagePath.trim(),
              title: office.name,
              loader: pictureLoader,
            ),
          ],
          const SizedBox(height: 18),
          StudentSectionLabel(
            supervisors.length > 1 ? 'SUPERVISORS' : 'SUPERVISOR',
          ),
          const SizedBox(height: 6),
          if (supervisors.isEmpty)
            const _Text(
              '',
              empty: 'No supervisor assigned yet.',
              icon: Icons.badge_outlined,
            )
          else
            for (var i = 0; i < supervisors.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _SupervisorRow(
                name: supervisors[i].name,
                avatar: avatars[supervisors[i].id],
              ),
            ],
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 18),
            const StudentSectionLabel('SKILLS THIS OFFICE LOOKS FOR'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final skill in skills)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.maroon50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      skill,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.maroon,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A supervisor: their picture (initials until they have one) and name.
class _SupervisorRow extends StatelessWidget {
  final String name;
  final String? avatar;
  const _SupervisorRow({required this.name, this.avatar});

  static String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    return (parts.length > 1 ? '$first${parts.last[0]}' : first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPicture = (avatar ?? '').isNotEmpty;
    void view() => showPictureViewer(context, pictureUrl: avatar!, title: name);
    final picture = UserAvatar(
      avatarUrl: avatar,
      initials: _initials(name),
      size: 40,
    );
    return Row(
      children: [
        // With a picture, tapping it enlarges it, like "View picture" below.
        if (hasPicture)
          Semantics(
            button: true,
            label: "View $name's picture",
            excludeSemantics: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(onTap: view, child: picture),
            ),
          )
        else
          picture,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate800,
                ),
              ),
              if (hasPicture)
                InkWell(
                  onTap: view,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.zoom_in_rounded,
                          size: 15,
                          color: AppTheme.maroon,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'View picture',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.maroon,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A value, or a quiet line saying the Head hasn't filled it in.
class _Text extends StatelessWidget {
  final String value;
  final String empty;
  final IconData? icon;
  const _Text(this.value, {required this.empty, this.icon});

  @override
  Widget build(BuildContext context) {
    final has = value.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 15,
              color: has ? AppTheme.slate500 : AppTheme.slate400,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            has ? value : empty,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: has ? AppTheme.slate800 : AppTheme.slate500,
              fontStyle: has ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: studentCardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: AppTheme.slate500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.slate600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
