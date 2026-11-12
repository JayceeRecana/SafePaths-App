/// Names transcribed from the LGU image supplied by the project team.
/// The post does not provide entrance coordinates or current opening status.
class MarulasEvacuationSites {
  static const sourceUrl =
      'https://www.facebook.com/photo?fbid=468942608601563&set=pcb.468955825266908';
  // Exclusion only: removed from the app's destinations at the team's request.
  static const removedNames = {'Do\u00f1a Ata Covered Court'};
  static List<String> searchNames(String name) =>
      name == 'Marulas Central Elementary School'
      ? [name, 'Marulas Central School']
      : [name];
  static const names = [
    '3S Center',
    'Barangay Hall',
    'Elysian Covered Court',
    'Constantino Elementary School',
    'San Miguel Heights Elementary School',
    'Serrano Elementary School',
    'Valenzuela National High School',
    'Marulas Central Elementary School',
    'Bitik Elementary School',
    'Do\u00f1a Ata Elementary School',
  ];
}
