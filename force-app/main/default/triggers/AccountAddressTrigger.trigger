trigger AccountAddressTrigger on Account (before insert, before update) {
    AccountTriggerHandler.handleAddressMatching(Trigger.new);
}
