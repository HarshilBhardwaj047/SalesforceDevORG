trigger DryRun8Test on Contact (before insert, before update) {
    for (Contact c : Trigger.new) {
        if (c.LastName == null) {
            c.LastName = 'Unknown';
        }
        System.debug('processing ' + c.Id);
        System.debug('line 2');
        System.debug('line 3');
        System.debug('line 4');
        System.debug('line 5');
        System.debug('line 6');
        System.debug('line 7');
        System.debug('line 8');
        System.debug('line 9');
        System.debug('line 10');
    }

    List<Account> accts = [SELECT Id FROM Account LIMIT 1];
    insert new Task(Subject = 'Follow up on ' + accts.size());
}
