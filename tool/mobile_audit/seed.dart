// Realistic data for the mobile audit: long-ish real-world names, titles
// and notes, so the pages show what they show on a real account.
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/task_duty.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _day(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

final _now = DateTime.now();
String _ago(int days) => _day(_now.subtract(Duration(days: days)));
// How the app stores them: an announcement from a Firestore Timestamp
// (DateTime.toString), a report as M/D/YYYY, the rest as ISO.
String _stamp(int daysAgo) =>
    _now.subtract(Duration(days: daysAgo)).toString();
String _mdy(int daysAgo) {
  final d = _now.subtract(Duration(days: daysAgo));
  return "${d.month}/${d.day}/${d.year}";
}

String _iso(int daysAgo) =>
    _now.subtract(Duration(days: daysAgo)).toUtc().toIso8601String();

const _cics = 'College of Information and Computing Sciences';
const _cba = 'College of Business and Accountancy';

final admin = User(
  id: 'admin1',
  name: 'Rosalinda M. Villanueva',
  email: 'admin@example.com',
  role: 'Admin',
);
final head = User(
  id: 'head1',
  name: 'Ramon Eduardo C. Pascual',
  email: 'head@example.com',
  role: 'Head',
  department: _cics,
);
final supervisor = User(
  id: 'sup1',
  name: 'Maria Concepcion S. Dimaculangan',
  email: 'supervisor@example.com',
  role: 'Supervisor',
  department: _cics,
  phone: '0917 123 4567',
);
final assistant = User(
  id: 'sa1',
  name: 'Kristine Joy D. Manalastas',
  email: 'kristine.manalastas@example.com',
  role: 'Student Assistant',
  department: _cics,
  campus: 'Main Campus (Boac)',
  studentId: '23B0001',
  saId: 'SA-2026-0012',
  courseProgram: 'Bachelor of Science in Information Technology',
  yearLevel: '3rd Year',
  skills: const ['Data encoding', 'Communication Skills', 'Web Developer'],
  acceptedAt: '2026-08-12T04:00:00.000Z',
);
final assistant2 = User(
  id: 'sa2',
  name: 'Mark Anthony P. Villareal',
  email: 'mark.villareal@example.com',
  role: 'Student Assistant',
  department: _cba,
  campus: 'Santa Cruz Campus',
  studentId: '22A0002',
  saId: 'SA-2026-0013',
);
final student = User(
  id: 'stu1',
  name: 'Angelo Nathaniel R. Santiago',
  email: 'angelo.santiago@example.com',
  role: 'Student',
  department: _cba,
  campus: 'Main Campus (Boac)',
  studentId: '24C0003',
);

User _userFor(String role) => switch (role) {
  'Admin' => admin,
  'Head' => head,
  'Supervisor' => supervisor,
  'Student' => student,
  _ => assistant,
};

AppState seededState(String role) {
  final state = AppState()
    ..currentUser = _userFor(role)
    ..users = [admin, head, supervisor, assistant, assistant2, student]
    ..skills = const [
      'Data encoding',
      'Communication Skills',
      'Web Developer',
      'Records Management',
      'Customer Service',
    ]
    ..students = [
      Student(
        id: 'sa1',
        userId: 'sa1',
        name: assistant.name,
        email: assistant.email,
        department: _cics,
        campus: 'Main Campus (Boac)',
        totalHours: 36.5,
      ),
      Student(
        id: 'sa2',
        userId: 'sa2',
        name: assistant2.name,
        email: assistant2.email,
        department: _cba,
        campus: 'Santa Cruz Campus',
        totalHours: 12,
      ),
    ]
    ..offices = [
      Office(
        id: 'o1',
        name: 'College of Information and Computing Sciences Dean\'s Office',
        code: 'CICS-DO',
        headIds: const ['sup1'],
        headNames: [supervisor.name],
        assistantIds: const ['sa1', 'sa2'],
        assistantNames: [assistant.name, assistant2.name],
        requiredSkills: const ['Data encoding', 'Communication Skills'],
        about:
            'Handles student records, class schedules and the faculty '
            'evaluation forms of the college.',
        location: 'CICS Building, 2nd floor, Room 204 beside the faculty lounge',
      ),
      Office(
        id: 'o2',
        name: 'University Library and Information Services',
        code: 'ULIS',
        headIds: const [],
        headNames: const [],
      ),
    ]
    ..tasks = [
      Task(
        id: 't1',
        title: 'Encode the midterm grades of BSIT 2A into the registrar sheet',
        description:
            'Use the new template; double-check the student numbers before '
            'saving.',
        status: 'In Progress',
        priority: 'High',
        dueDate: _ago(-3),
        assignedTo: 'sa1',
        assignedToName: assistant.name,
        assignedBy: 'sup1',
        category: 'Administrative',
        checklistItems: const ['Open the sheet', 'Encode', 'Have it checked'],
      ),
      Task(
        id: 't2',
        title: 'Sort and file the incoming memos from the Office of the President',
        description: '',
        status: 'Completed',
        priority: 'Medium',
        dueDate: _ago(2),
        assignedTo: 'sa1',
        assignedToName: assistant.name,
        assignedBy: 'sup1',
        category: 'General',
        completedAt: _ago(1),
        reviewStatus: 'Pending',
      ),
      Task(
        id: 't3',
        title: 'Update the bulletin board',
        description: 'Remove the expired notices.',
        status: 'Completed',
        priority: 'Low',
        dueDate: _ago(6),
        assignedTo: 'sa2',
        assignedToName: assistant2.name,
        assignedBy: 'sup1',
        category: 'General',
        completedAt: _ago(5),
        reviewStatus: 'Approved',
      ),
      Task(
        id: 't4',
        title: 'Prepare the attendance sheets for the faculty meeting',
        description: '',
        status: 'Not Started',
        priority: 'Medium',
        dueDate: _ago(-7),
        assignedTo: 'sa2',
        assignedToName: assistant2.name,
        assignedBy: 'sup1',
        category: 'Administrative',
      ),
    ]
    ..taskDuties = [
      TaskDuty(
        id: 'd1',
        title: 'Front desk: answer walk-in inquiries',
        description: 'Log each visitor in the logbook.',
        category: 'General',
        assignedTo: 'sa1',
        assignedToName: assistant.name,
        assignedBy: 'sup1',
        academicYear: '2026-2027',
      ),
    ]
    ..attendance = [
      AttendanceRecord(
        id: 'a1',
        studentId: 'sa1',
        studentName: assistant.name,
        date: _ago(1),
        timeIn: '8:02 AM',
        timeOut: '11:58 AM',
        totalHours: 3.9,
      ),
      AttendanceRecord(
        id: 'a2',
        studentId: 'sa1',
        studentName: assistant.name,
        date: _ago(2),
        timeIn: '1:05 PM',
        isInvalid: true,
      ),
      AttendanceRecord(
        id: 'a3',
        studentId: 'sa2',
        studentName: assistant2.name,
        date: _ago(1),
        timeIn: '9:00 AM',
        timeOut: '12:00 PM',
        totalHours: 3,
        editedBy: head.name,
        editedAt: _iso(1),
        editNote: 'Time-out recorded at 12:00 PM',
      ),
    ]
    ..reports = [
      Report(
        id: 'r1',
        applicantId: 'sa1',
        title: 'Accomplishment Report for the month of October 2026',
        content: '• Encode the midterm grades\n• Sort and file the memos',
        studentName: assistant.name,
        status: 'Pending',
        submittedAt: _mdy(3),
      ),
      Report(
        id: 'r2',
        applicantId: 'sa2',
        title: 'Weekly report',
        content: '• Update the bulletin board',
        studentName: assistant2.name,
        status: 'Rejected',
        feedback: 'Please attach the signed DTR for the second week.',
        submittedAt: _mdy(9),
      ),
    ]
    ..announcements = [
      Announcement(
        id: 'call1',
        title: 'Hiring: Student Assistants for the 1st Semester, AY 2026-2027',
        body:
            'Marinduque State University is accepting applications for '
            'student assistants. Upload the requirements below before the '
            'deadline.',
        postedBy: head.name,
        postedByRole: 'Head',
        postedById: 'head1',
        postedAt: _stamp(4),
        deadline: _ago(-10),
        requirements: const [
          'Certificate of Registration',
          'Certified True Copy of Grades',
          'Barangay Certificate of Indigency',
        ],
        acceptsApplications: true,
        academicYear: '2026-2027',
      ),
      Announcement(
        id: 'req1',
        title: 'Request: two assistants for records digitization',
        body: 'We need help scanning and encoding the 2019-2024 records.',
        postedBy: supervisor.name,
        postedByRole: 'Supervisor',
        postedById: 'sup1',
        postedAt: _stamp(2),
        slots: '2',
        officeId: 'o1',
        officeName: 'College of Information and Computing Sciences Dean\'s Office',
        approvalStatus: 'Pending',
        isOpen: false,
        acceptsApplications: false,
        skills: const ['Data encoding', 'Records Management'],
      ),
    ]
    ..applications = [
      Application(
        id: 'app_stu1_2026-2027',
        announcementId: 'call1',
        announcementTitle:
            'Hiring: Student Assistants for the 1st Semester, AY 2026-2027',
        applicantId: 'stu1',
        applicantName: student.name,
        appliedAt: _iso(2),
        status: 'Pending',
        skills: const ['Customer Service', 'Communication Skills'],
        academicYear: '2026-2027',
      ),
      Application(
        id: 'app_sa2_2026-2027',
        announcementId: 'call1',
        announcementTitle:
            'Hiring: Student Assistants for the 1st Semester, AY 2026-2027',
        applicantId: 'sa2',
        applicantName: assistant2.name,
        appliedAt: _iso(20),
        status: 'Approved',
        academicYear: '2026-2027',
      ),
    ]
    ..notifications = [
      for (final uid in ['admin1', 'head1', 'sup1', 'sa1', 'stu1']) ...[
        AppNotification(
          id: 'n1_$uid',
          userId: uid,
          title: 'Task Awaiting Approval',
          message:
              '${assistant.name} completed "Sort and file the incoming memos '
              'from the Office of the President" and is waiting for approval.',
          type: 'task',
          createdAt: _ago(0),
        ),
        AppNotification(
          id: 'n2_$uid',
          userId: uid,
          title: 'Academic Year Ending Soon',
          message: 'AY 2026-2027 ends in 7 days.',
          type: 'academic_year',
          createdAt: _ago(3),
          isRead: true,
        ),
      ],
    ]
    ..headForwards = [
      HeadForward(
        id: 'f1',
        type: 'dtr_report',
        studentId: 'sa1',
        studentName: assistant.name,
        title: 'DTR/Accomplishment Report — October 2026',
        fileName: 'DTR_Accomplishment_Report_Manalastas_October_2026.docx',
        sentByName: supervisor.name,
        sentById: 'sup1',
        sentAt: _iso(2),
      ),
    ]
    ..payrollRecords = [
      PayrollRecord(
        id: 'p1',
        studentId: 'sa1',
        studentName: assistant.name,
        saId: assistant.saId,
        office: 'College of Information and Computing Sciences Dean\'s Office',
        campus: 'Main Campus (Boac)',
        department: _cics,
        periodStart: '2026-10-01',
        periodEnd: '2026-10-31',
        periodLabel: 'October 2026',
        dtrVerified: true,
        reportVerified: true,
        status: 'Approved',
      ),
    ];
  return state;
}
