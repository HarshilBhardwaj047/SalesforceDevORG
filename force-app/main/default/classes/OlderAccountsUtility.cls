public with sharing class OlderAccountsUtility {
    /**
     * Marks the 5 oldest Accounts as Heritage Accounts.
     * Uses USER_MODE so the running user's CRUD/FLS is enforced.
     */
    public static void updateOlderAccounts() {
        List<Account> oldAccounts = [
            SELECT Id, Description
            FROM Account
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT 5
        ];
        for (Account acct : oldAccounts) {
            acct.Description = 'Heritage Account';
        }
        if (!oldAccounts.isEmpty()) {
            update oldAccounts;
        }
    }
}
