public class AccountHandler {
   public static Account insertNewAccount(String accname){
    try{
    Account acct = new Account();
    acct.Name = accname;
    insert acct;
    return acct;
    } catch(DmlException e){
      System.debug('DML Exception: ' + e.getMessage());
      return null;
    }
   }
}