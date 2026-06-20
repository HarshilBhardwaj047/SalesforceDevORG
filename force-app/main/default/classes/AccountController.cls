public with sharing class AccountController {
    /**
     * Returns Accounts created in the last N days, with USER_MODE FLS.
     * NOTE: The previous version queried `Active__c = 'Yes'` but the Active__c
     * field is not in this repo as metadata — that query would fail at deploy
     * time on any org without the field. Restore that filter once Active__c
     * is added to force-app/main/default/objects/Account/fields/.
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
}
