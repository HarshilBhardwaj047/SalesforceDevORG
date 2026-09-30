public class AccountBulkUpdater {
    /**
     * Intentionally bad implementation — dry run of docs/WORKFLOW.md's
     * PR review bot, to verify the static rules engine actually detects
     * real anti-patterns (SOQL-in-loop, DML-in-loop, missing security
     * mode, missing sharing declaration). Not intended to be merged.
     */
    public static void touchAccountsBadly(List<Id> accountIds) {
        for (Id accId : accountIds) {
            Account acc = [SELECT Id, Name FROM Account WHERE Id = :accId LIMIT 1];
            acc.Name = acc.Name + ' (touched)';
            update acc;
        }
    }
}
