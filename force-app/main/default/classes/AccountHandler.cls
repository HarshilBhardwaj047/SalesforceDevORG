public class AccountHandler {
    public static Id insertNewAccount(String acctname) {
        Account acct = new Account(Name = 'Devops');
        try {
            insert acct;
            return (acct.Id);
        } catch (DMLException e) {
            System.debug('DML Exception: ' + e.getMessage());
            return null;
        }
     
    }
}
