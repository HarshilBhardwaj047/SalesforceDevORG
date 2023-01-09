public with sharing class AccountHandler {
    public static Id insertNewAccount(String acctname) {
        try {
            Account acct = new Account(Name = 'Devops');
            insert acct;
            return (acct.Id);
        } catch (DMLException e) {
            System.debug('DML Exception: ' + e.getMessage());
            return null;
        }
     
    }
}
