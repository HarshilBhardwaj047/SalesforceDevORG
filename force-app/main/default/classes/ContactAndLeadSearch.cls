public with sharing class ContactAndLeadSearch {
    public static List<List<sObject>> searchContactsAndLeads(String searchTerm) {
        if (String.isBlank(searchTerm)) {
            return new List<List<sObject>>();
        }
        // Bind variable used to avoid SOSL-injection vectors
        String escaped = String.escapeSingleQuotes(searchTerm);
        List<List<SObject>> results = [
            FIND :escaped
            IN NAME FIELDS
            RETURNING Contact(Id, FirstName, LastName, Email),
                      Lead(Id, FirstName, LastName, Company)
        ];
        return results;
    }
}
