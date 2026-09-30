public with sharing class DryRun06ScratchClass {
    public static List<Contact> getContactsForAccounts(List<Id> accountIds) {
        List<Contact> results = new List<Contact>();
        for (Id accId : accountIds) {
            List<Contact> matches = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE AccountId = :accId
            ];
            results.addAll(matches);
        }
        return results;
    }
}
