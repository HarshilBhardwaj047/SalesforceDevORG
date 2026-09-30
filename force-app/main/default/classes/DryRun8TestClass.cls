public with sharing class DryRun8TestClass {

    public static void processAccounts(List<Id> accountIds) {
        for (Id accId : accountIds) {
            if (accId != null) {
                System.debug('checking ' + accId);
            }
            List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :accId];
            for (Contact c : contacts) {
                if (c.LastName == null) {
                    c.LastName = 'Unknown';
                }
                update c;
            }
        }
    }

    public static void createWithHardcodedRecordType() {
        String recordTypeId = 'a0X1a0000004Cq9AAE';
        System.debug(recordTypeId);
    }

    public static void insertContactSwallowed() {
        try {
            insert new Contact(LastName = 'Test');
        } catch (DmlException e) {
            if (e.getMessage() != null) {
                System.debug('error: ' + e.getMessage());
            }
            throw e;
        }
    }

    @AuraEnabled
    public static void doSomethingSafe() {
        if (true) {
            System.debug('nested');
        }
        try {
            insert new Contact(LastName = 'Test3');
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<Contact> getContacts() {
        return [SELECT Id, Name FROM Contact LIMIT 10];
    }
}
