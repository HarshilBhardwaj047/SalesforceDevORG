public with sharing class AccountHandler {
    /**
     * Inserts a new Account with the given name.
     * Throws AuraHandledException so callers (LWC/Aura) get a friendly message;
     * full DML detail is logged for debugging.
     */
    public static Account insertNewAccount(String accname) {
        if (String.isBlank(accname)) {
            throw new IllegalArgumentException('Account name is required.');
        }
        try {
            if (!Schema.sObjectType.Account.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create Accounts.');
            }
            Account acct = new Account(Name = accname);
            insert acct;
            return acct;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'AccountHandler DML failure: ' + e.getMessage());
            throw new AuraHandledException('Failed to insert Account: ' + e.getDmlMessage(0));
        }
    }
}
