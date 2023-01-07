public class OlderAccountsUtility {
    public static void updateOlderAccounts() {
        // get the 5 oldest accounts
        Account[] oldAccounts = [ SELECT Id, Description FROM Account ORDER BY CreatedDate ASC LIMIT 5];
        // loop through them and update the description field
         for (Account acct : oldAccounts){
        acct.Description = 'Heritage Account';
      }
        // save the changes you made
        update oldAccounts;
    }
}