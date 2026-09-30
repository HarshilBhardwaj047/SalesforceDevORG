trigger DryRun06ScratchTrigger on Account (after insert) {
    List<Contact> related = [
        SELECT Id, Name
        FROM Contact
        WHERE AccountId IN :Trigger.newMap.keySet()
    ];
    System.debug(related);
}
