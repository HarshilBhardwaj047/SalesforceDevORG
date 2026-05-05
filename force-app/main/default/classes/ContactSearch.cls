public with sharing class ContactSearch {
    public static List<Contact> searchForContacts(String lastName, String mailingPostalCode) {
        if (String.isBlank(lastName)) {
            return new List<Contact>();
        }
        return [
            SELECT Id, Name
            FROM Contact
            WHERE LastName = :lastName
              AND MailingPostalCode = :mailingPostalCode
            WITH USER_MODE
            LIMIT 200
        ];
    }
}
