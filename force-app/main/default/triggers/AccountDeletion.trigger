trigger AccountDeletion on Account (before delete) {
    AccountTriggerHandler.preventDeletionWhenOpportunitiesExist(Trigger.old, Trigger.oldMap);
}
