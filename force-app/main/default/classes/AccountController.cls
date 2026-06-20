public with sharing class AccountController {
    /**
     * Returns Accounts created in the last N days, with USER_MODE FLS.
     * NOTE: The previous version queried `Active__c = 'Yes'` but the Active__c
     * field is not in this repo as metadata — that query would fail at deploy
     * time on any org without the field. Restore that filter once Active__c
     * is added to force-app/main/default/objects/Account/fields/.
     * TEST-101
     */
    @AuraEnabled(cacheable=true)
    public static List<Account> getRecentAccounts(Integer days) {
        Integer windowDays = (days == null || days <= 0) ? 30 : days;
        DateTime cutoff = DateTime.now().addDays(-windowDays);
        return [
            SELECT Id, Name, CreatedDate
            FROM Account
            WHERE CreatedDate >= :cutoff
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Integer getRecentAccountCount(Integer days) {
        Integer windowDays = (days == null || days <= 0) ? 30 : days;
        DateTime cutoff = DateTime.now().addDays(-windowDays);
        return [
            SELECT COUNT()
            FROM Account
            WHERE CreatedDate >= :cutoff
            WITH USER_MODE
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Account> getAccountsByName(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [
            SELECT Id, Name, CreatedDate
            FROM Account
            WHERE Name LIKE :term
            WITH USER_MODE
            ORDER BY Name
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Account> getTopAccounts(Integer topN) {
        Integer n = (topN == null || topN <= 0) ? 10 : topN;
        return [
            SELECT Id, Name, CreatedDate
            FROM Account
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :n
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Account getAccountById(Id accountId) {
        List<Account> results = [
            SELECT Id, Name, CreatedDate
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        return results.isEmpty() ? null : results[0];
    }

    @AuraEnabled(cacheable=true)
    public static Integer countAllAccounts() {
        return [SELECT COUNT() FROM Account WITH USER_MODE];
    }

    @AuraEnabled(cacheable=true)
    public static List<Account> getAccountsModifiedToday() {
        Date today = Date.today();
        return [
            SELECT Id, Name, LastModifiedDate
            FROM Account
            WHERE LastModifiedDate = TODAY
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 100
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Account> getAccountsWithPhone() {
        return [
            SELECT Id, Name, Phone
            FROM Account
            WHERE Phone != null
            WITH USER_MODE
            ORDER BY Name
            LIMIT 100
        ];
    }
}
