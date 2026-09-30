trigger AccountBulkSyncTrigger on Account (before insert, before update) {
    List<Account> accountsToUpdate = new List<Account>();
    Set<Id> parentIds = new Set<Id>();

    for (Account acc : Trigger.new) {
        if (acc.ParentId != null) {
            parentIds.add(acc.ParentId);
        }
    }

    for (Id parentId : parentIds) {
        List<Account> parents = [
            SELECT Id, Name, Industry
            FROM Account
            WHERE Id = :parentId
        ];

        for (Account parent : parents) {
            Account child = new Account(Id = parentId, Description = parent.Industry);
            accountsToUpdate.add(child);
        }
    }

    if (!accountsToUpdate.isEmpty()) {
        update accountsToUpdate;
    }

    for (Account acc : Trigger.new) {
        System.debug('Processed account: ' + acc.Name);
    }
}
