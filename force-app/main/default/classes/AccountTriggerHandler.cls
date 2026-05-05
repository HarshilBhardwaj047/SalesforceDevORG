/**
 * Handler for Account triggers. Centralises the logic so triggers stay thin
 * and so recursion can be guarded for the lifetime of one transaction.
 */
public with sharing class AccountTriggerHandler {

    // Recursion guard — set to true after first run-through in a transaction
    private static Boolean addressMatchingRunOnce = false;

    /**
     * Copies BillingPostalCode to ShippingPostalCode when the
     * Match_Billing_Address__c flag is set.
     * Operates on Trigger.new in a before-context so no DML is needed.
     */
    public static void handleAddressMatching(List<Account> newAccounts) {
        if (addressMatchingRunOnce) return;
        addressMatchingRunOnce = true;

        for (Account acc : newAccounts) {
            if (acc.Match_Billing_Address__c == true) {
                acc.ShippingPostalCode = acc.BillingPostalCode;
            }
        }
    }

    /**
     * Prevents deletion of Accounts that still have related Opportunities.
     * The SOQL is bulk-safe — one query for the whole batch — and uses USER_MODE
     * so the running user's CRUD/FLS is enforced.
     */
    public static void preventDeletionWhenOpportunitiesExist(
        List<Account> oldAccounts,
        Map<Id, Account> oldMap
    ) {
        Set<Id> accountIds = oldMap.keySet();
        if (accountIds.isEmpty()) return;

        // Single bulk query — never inside a loop
        Set<Id> accountsWithOpps = new Set<Id>();
        for (Opportunity opp : [
            SELECT AccountId
            FROM Opportunity
            WHERE AccountId IN :accountIds
            WITH USER_MODE
        ]) {
            accountsWithOpps.add(opp.AccountId);
        }

        for (Id accId : accountsWithOpps) {
            oldMap.get(accId).addError('Cannot delete Account with related Opportunities.');
        }
    }
}
